# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded CE142-triggered CE143 acquisition owns exact peer/worker generations independently of public requests.
## Detached hash-checked content never mutates canonical state or certifies GP admission.
import std/[monotimes, times, assertions]
import ./services
import ./proof/worker
import ../jamnp-s/[node, connections, read_stream, read_client, read_validation,
    preimage_announcement, preimage_cache]
import ../codec/bounded
import ../codec/state/requests

type
  FetchPhase {.pure.} = enum ## One active transfer/verification shares capacity with eight fixed queued intents.
    Empty, Queued, Receiving, Waiting, Verifying
  FetchEntry = object ## Peer tokens and fixed claims grant no canonical graph alias.
    phase: FetchPhase
    peer: NodePeer
    notice: PreimageAnnouncement
    started: MonoTime
    network: NodeRequestTicket
    worker: ProofWorkerTicket
    wire: seq[byte]
    cancelled: bool
  PreimageFollowups* = object ## Stable noncopyable main-thread owner must retire its exact tickets before destruction.
    entries: array[8, FetchEntry]
    count, cursor: int
    active: int
    cache: PreimageCache
proc `=copy`*(destination: var PreimageFollowups, source: PreimageFollowups) {.error.}
  ## Copying would duplicate cancellation authority over network/CPU resources.
proc `=dup`*(source: PreimageFollowups): PreimageFollowups {.error.}
  ## Initialization also cannot duplicate the resource owner.
proc `=wasMoved`*(owner: var PreimageFollowups) {.nodestroy, requires: owner.count == 0.} =
  ## Only a retired owner may transfer storage.
  `=wasMoved`(owner.entries)
  `=wasMoved`(owner.cache)
  owner.count = 0
  owner.cursor = 0
  owner.active = -1
proc requireClosed(owner: PreimageFollowups) {.requires: owner.count == 0.} =
  ## All operation authority must have been explicitly retired.
  discard
proc `=destroy`*(owner: PreimageFollowups) =
  ## Destruction never silently cancels or joins a borrowed Services owner.
  requireClosed(owner)
  `=destroy`(owner.entries)
  `=destroy`(owner.cache)
proc reset*(owner: var PreimageFollowups) {.requires: owner.count == 0.} =
  ## Reopening discards retained content and all historical peer generations.
  owner.cache.clear()
  owner.active = -1
  owner.cursor = 0
func pendingCount*(owner: PreimageFollowups): int =
  ## Count fixed queued and active intents, including cancelled uncollected CPU work.
  owner.count
func cachedCount*(owner: PreimageFollowups): int =
  ## Detached statistics remain safe while Services is exclusively leased.
  owner.cache.len
func cachedBytes*(owner: PreimageFollowups): int =
  ## Logical wire bytes exclude bounded transient copies.
  owner.cache.byteLength
proc retain*(owner: var PreimageFollowups, checked: CheckedReadReply): PreimageCacheError =
  ## Only the sealed whole-content verifier can populate the cache.
  owner.cache.remember(checked)
proc find*(owner: var PreimageFollowups, request: ReadRequest): PreimageCacheResult =
  ## Frozen exact hash/method binding is preserved for the native responder.
  owner.cache.find(request)
proc fetchRequest(notice: PreimageAnnouncement): ReadRequest {.requires: notice.valid.} =
  ## Fetch on CE143 carries the full hash and no untrusted service-selected state key.
  let identity = array[32, byte](notice.hash)
  decodeReadRequest(ReadKind.Preimage, identity).value
proc held(owner: PreimageFollowups, notice: PreimageAnnouncement): bool =
  ## Exact length and full identity suppress redundant retrieval without copying blob bytes.
  owner.cache.contains(fetchRequest(notice), uint32(notice.length))
proc drop(owner: var PreimageFollowups, index: int) {.requires: index >= 0 and index < 8.} =
  ## Caller has retired any native/CPU ticket before dropping detached storage.
  assert owner.entries[index].phase != FetchPhase.Empty
  owner.entries[index] = default(FetchEntry)
  dec owner.count
  if owner.active == index: owner.active = -1
proc enqueue*(owner: var PreimageFollowups, streams: NodeService, peer: NodePeer,
    notice: PreimageAnnouncement, clock: MonoTime): bool =
  ## Fixed capacity and identity/length deduplication precede accepting followup responsibility.
  if not notice.valid or not streams.peerLive(peer): return false
  if owner.held(notice): return true
  for index in 0..<8:
    if owner.entries[index].phase != FetchPhase.Empty:
      let previous = owner.entries[index].notice
      if array[32, byte](previous.hash) == array[32, byte](notice.hash) and uint32(
          previous.length) == uint32(notice.length):
        return true # One hash-checked blob serves every service requesting these exact bytes.
  if owner.count >= 8: return false
  for index in 0..<8:
    if owner.entries[index].phase == FetchPhase.Empty:
      owner.entries[index] = FetchEntry(phase: FetchPhase.Queued, peer: peer,
          notice: notice, started: clock)
      inc owner.count
      return true
  false
proc close*(owner: var PreimageFollowups, services: var Services, streams: var NodeService) =
  ## Only successful exact cancellation authorizes joining the shared worker; foreign leases survive unchanged.
  for index in 0..<8:
    case owner.entries[index].phase
    of FetchPhase.Verifying:
      if services.cancelStateProof(owner.entries[index].worker): services.stopStateProofs()
    of FetchPhase.Receiving:
      discard streams.cancelRequest(owner.entries[index].network)
    else: discard # Queued/waiting entries own only detached bytes and fixed peer tokens.
    owner.entries[index] = default(FetchEntry)
  owner.count = 0
  owner.reset()
proc poll*(owner: var PreimageFollowups, services: var Services,
    streams: var NodeService, clock: MonoTime) =
  ## Work per host turn is bounded by eight slots; no canonical alias is acquired here.
  if owner.count == 0: return
  if owner.active >= 0:
    let index = owner.active
    let expired = clock < owner.entries[index].started or
        (clock-owner.entries[index].started).inMilliseconds >= 120000
    if owner.entries[index].phase == FetchPhase.Verifying:
      if expired and not owner.entries[index].cancelled:
        owner.entries[index].cancelled = true
        discard services.cancelStateProof(owner.entries[index].worker)
      if services.stateProofPhase notin [ProofWorkerPhase.Queued, ProofWorkerPhase.Running]:
        let completed = services.collectStateProof(owner.entries[index].worker)
        if not owner.entries[index].cancelled and completed.kind ==
            ProofWorkerCompletionKind.ReadVerified:
          let checked = completed.verifiedReadValue
          if checked.error == ReadVerificationError.None and checked.value.kind ==
              ReadKind.Preimage:
            discard owner.cache.remember(checked.value)
        owner.drop(index) # Failed/stale collection cannot retain content or retire a foreign lease.
    elif expired:
      if owner.entries[index].phase == FetchPhase.Receiving:
        discard streams.cancelRequest(owner.entries[index].network)
      owner.drop(index)
    elif owner.entries[index].phase == FetchPhase.Receiving:
      let completed = streams.takeReply(owner.entries[index].network)
      if completed.error == ReadError.None:
        let wire = completed.value.bytes
        if wire.len == int(uint32(owner.entries[index].notice.length))+4:
          owner.entries[index].wire = wire
          owner.entries[index].network = default(NodeRequestTicket)
          owner.entries[index].phase = FetchPhase.Waiting
        else:
          owner.drop(index) # Exact advertised length is checked before hashing or retention.
      elif completed.error != ReadError.Unavailable:
        discard streams.cancelRequest(owner.entries[index].network)
        owner.drop(index)
  if owner.active >= 0: return
  for offset in 0..<8:
    let index = (owner.cursor+offset) mod 8
    if owner.entries[index].phase != FetchPhase.Queued: continue
    let notice = owner.entries[index].notice
    if clock < owner.entries[index].started or
        (clock-owner.entries[index].started).inMilliseconds >= 120000 or
        not streams.peerLive(owner.entries[index].peer) or owner.held(notice):
      owner.drop(index)
      continue # Closure never causes dialing a replacement peer or reusing its generation.
    let admitted = streams.request(owner.entries[index].peer, fetchRequest(notice),
        ByteLimit(uint32(notice.length)+4))
    if admitted.error == NodeError.None:
      owner.entries[index].network = admitted.value
      owner.entries[index].phase = FetchPhase.Receiving
      owner.active = index
      owner.cursor = (index+1) mod 8
      return
    if admitted.error notin [NodeError.Unavailable, NodeError.LimitExceeded]:
      owner.drop(index) # Temporary quotas preserve bounded queued intent; other refusals retire it.
proc submitWaiting*(owner: var PreimageFollowups, services: var Services): bool {.raises.} =
  ## Host arbitration gives this private verification one turn without occupying the caller's checked slot.
  if owner.count == 0 or owner.active < 0: return false
  let index = owner.active
  if owner.entries[index].phase != FetchPhase.Waiting: return false
  let limits = ReadVerificationLimits(wireBytes: ByteLimit(MaxReadReplyBytes))
  let admitted = services.beginReadVerification(fetchRequest(owner.entries[index].notice),
      owner.entries[index].wire, limits)
  if admitted.error == StateProofAdmissionError.Busy: return false
  if admitted.error == StateProofAdmissionError.None:
    owner.entries[index].worker = admitted.value
    owner.entries[index].wire = @[]
    owner.entries[index].phase = FetchPhase.Verifying
  else:
    owner.drop(index) # Admission failures never turn detached bytes into checked content.
  true
