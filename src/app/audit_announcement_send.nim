# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached CE144 uploads fan out to original auditors through bounded native request and demand-dial slots.
import std/[monotimes, times]
import ./proof/work_submission
import ../jamnp-s/[node, connections, endpoints, read_stream, read_client]
import ../codec/bounded

const ParallelAuditors = 8 ## Leave native request capacity for other foreground protocol actors.
type
  Delivery = object ## Each slot retires only the native authorities it reserved.
    occupied, requesting, dialing, retiring, closing: bool
    index, attempts: int
    request: NodeRequestTicket
    dial: DialTicket
    deadline, retry: MonoTime
  AuditAnnouncementSend* = object ## One bounded announcement owns at most eight exact delivery attempts concurrently.
    active: bool
    request: ReadRequest
    recipients: seq[InitialAuditRecipient]
    cursor, settled, acknowledged: int
    timeout, retry: int
    attempts: int
    slots: array[ParallelAuditors, Delivery]

proc `=copy`*(destination: var AuditAnnouncementSend, source: AuditAnnouncementSend) {.error.}
  ## Cancellation authority is unique to the foreground controller.
proc `=dup`*(source: AuditAnnouncementSend): AuditAnnouncementSend {.error.}
  ## Copying an active or pending fan-out would duplicate native authority.
proc requireIdle(owner: AuditAnnouncementSend) {.requires: not owner.active.} =
  ## All native authorities must be retired or cancelled explicitly before destruction.
  discard
proc `=wasMoved`*(owner: var AuditAnnouncementSend) {.nodestroy, requires: not owner.active.} =
  ## Only idle, detached storage may move.
  `=wasMoved`(owner.request)
  `=wasMoved`(owner.recipients)
  `=wasMoved`(owner.slots)
proc `=destroy`*(owner: AuditAnnouncementSend) =
  ## The application closes the actor before closing its native node.
  requireIdle(owner)
  `=destroy`(owner.request)
  `=destroy`(owner.recipients)
  `=destroy`(owner.slots)
func sending*(owner: AuditAnnouncementSend): bool =
  ## Delivery is active until all targets have acknowledged or exhausted their attempts.
  owner.active
func acknowledged*(owner: AuditAnnouncementSend): int =
  ## Bare FIN confirms receipt only.
  owner.acknowledged
proc begin*(owner: var AuditAnnouncementSend, produced: ProducedInitialAudit,
    attempts, timeoutMs, retryMs: int): bool =
  ## An empty selection has no wire obligation and never enters the delivery actor.
  if attempts notin 1..4 or timeoutMs notin 1..120000 or retryMs notin 1..120000:
    return false
  if owner.active or not produced.request.valid or produced.request.kind !=
      ReadKind.AuditAnnouncement:
    return false
  if produced.selected.count notin 1..10 or produced.recipients.len > 1023: return false
  owner.request = produced.request
  owner.recipients = produced.recipients
  owner.cursor = 0
  owner.settled = 0
  owner.acknowledged = 0
  owner.timeout = timeoutMs
  owner.retry = retryMs
  owner.attempts = attempts
  owner.active = owner.recipients.len > 0
  true
proc finish(owner: var AuditAnnouncementSend, slot: var Delivery, streams: var NodeService,
    clock: MonoTime, received: bool) =
  ## Release the exact request and schedule a retry only after any demand dial has retired.
  if slot.requesting: discard streams.cancelRequest(slot.request)
  slot.requesting = false
  slot.request = default(NodeRequestTicket)
  slot.retiring = true
  slot.retry = clock+initDuration(milliseconds = owner.retry)
  if received:
    inc owner.acknowledged
    slot.attempts = owner.attempts
proc advance(owner: var AuditAnnouncementSend, slot: var Delivery, streams: var NodeService,
    clock: MonoTime) =
  ## Each turn observes one request or one dial; deadlines also bound waits for native capacity.
  let member = owner.recipients[slot.index]
  let expired = clock >= slot.deadline
  if slot.retiring:
    if slot.dialing:
      if not streams.peerConnectionLive(slot.dial):
        slot.dialing = false
        slot.closing = false
      elif not slot.closing and (expired or not streams.peerBusy(member.identity)):
        slot.closing = streams.cancelPeerConnection(slot.dial)
      return
    if slot.attempts >= owner.attempts:
      slot = default(Delivery)
      inc owner.settled
    elif clock >= slot.retry:
      slot.retiring = false
      slot.deadline = clock+initDuration(milliseconds = owner.timeout)
      inc slot.attempts
    return
  if slot.requesting:
    let reply = streams.takeReply(slot.request)
    if reply.error == ReadError.None:
      slot.requesting = false
      owner.finish(slot, streams, clock, true)
    elif reply.error != ReadError.Unavailable or expired: owner.finish(slot, streams, clock, false)
    return
  if expired:
    owner.finish(slot, streams, clock, false)
    return
  let peer = streams.peerForIdentity(member.identity)
  if peer.error == NodeError.None:
    let sent = streams.request(peer.value, owner.request, ByteLimit(0))
    if sent.error == NodeError.None:
      slot.request = sent.value
      slot.requesting = true
    elif sent.error notin [NodeError.Unavailable, NodeError.LimitExceeded]:
      owner.finish(slot, streams, clock, false)
  elif not slot.dialing and member.endpoint.error == EndpointError.None:
    let dial = streams.beginPeerConnection(member.identity, member.endpoint.value)
    if dial.error == DialError.None:
      slot.dial = dial.value
      slot.dialing = true
    elif dial.error != DialError.Unavailable:
      owner.finish(slot, streams, clock, false)
proc poll*(owner: var AuditAnnouncementSend, streams: var NodeService, clock: MonoTime) =
  ## Rotate through a fixed number of independent slots and never traverse the original roster in the node loop.
  if not owner.active or not streams.isOpen: return
  for index in 0..<owner.slots.len:
    # Borrow the slot locally so the whole actor and a mutable slot never alias across a call.
    var slot = owner.slots[index]
    if not slot.occupied and owner.cursor < owner.recipients.len:
      slot = Delivery(occupied: true, index: owner.cursor, attempts: 1,
          deadline: clock+initDuration(milliseconds = owner.timeout))
      inc owner.cursor
    if slot.occupied: owner.advance(slot, streams, clock)
    owner.slots[index] = slot
  if owner.settled == owner.recipients.len:
    owner.active = false
    owner.request = default(ReadRequest)
    owner.recipients = @[]
proc close*(owner: var AuditAnnouncementSend, streams: var NodeService) =
  ## Native buffers remain owned by NodeService while physical cancellations finish.
  for slot in owner.slots:
    # Reset only streams and temporary connections admitted by this actor.
    if slot.requesting: discard streams.cancelRequest(slot.request)
    if slot.dialing: discard streams.cancelPeerConnection(slot.dial)
  owner.slots = default(array[ParallelAuditors, Delivery])
  owner.active = false
  owner.request = default(ReadRequest)
  owner.recipients = @[]
