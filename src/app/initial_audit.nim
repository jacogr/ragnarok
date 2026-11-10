# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optional initial declarations traverse retained selected history under the shared proof-worker lease.

import std/[monotimes, times]
import ./[services, audit_announcement_send, audit_state, audit_branches]
import ./proof/[worker, work_submission]
import ../jamnp-s/[node, audits, audit_context, audit_validation, audit_origin, audit_registry]
import ../chain/[genesis, provider]
import ../codec/bounded
from ../codec/disputes import JudgeIndex

type
  InitialAuditPolicy* = object ## Explicit bounded signing, history verification and delivery.
    context: AuditContextLimits
    proof: AuditProofLimits
    origin: AuditOriginLimits
    ready: bool
    attempts, timeout, retry, maxDeclarations: int
  InitialAuditDeclaration* = object ## Fixed retained obligations survive network attempts and later information.
    record*: AuditAnnouncement
    selected*: InitialAuditSelection
    reportOrdinals*: array[10, int]
    origin*: AuditOriginId
    epoch*: uint64
  InitialAudits* = object ## One exact worker ticket and bounded detached declaration and delivery storage.
    policy: InitialAuditPolicy
    broadcast: AuditAnnouncementSend
    ticket: ProofWorkerTicket
    working, pinning: bool
    side, preferSide: bool
    sideAfter, sideSerial: uint64
    prepared: ProducedInitialAudit
    afterSlot, slot, minimumEpoch: uint64
    blockHash: genesis.BlockHash
    ordinal: uint16
    retry: MonoTime
    declarations: seq[InitialAuditDeclaration]

func initialAuditPolicy*(context: AuditContextLimits, proof: AuditProofLimits,
    origin: AuditOriginLimits, attempts: range[1..4] = 2, timeoutMs: range[1..120000] = 1000,
    retryMs: range[1..120000] = 250, declarations: range[1..32768] = 256): InitialAuditPolicy =
  ## Defaults carry no authority. Reserve signing and verification before worker admission.
  if not context.valid or not origin.valid or not proof.valid or uint64(proof.proofs) < 2:
    return default(InitialAuditPolicy)
  InitialAuditPolicy(ready: true, context: context, proof: proof, origin: origin,
      attempts: attempts, timeout: timeoutMs, retry: retryMs, maxDeclarations: declarations)

proc `=copy`*(destination: var InitialAudits, source: InitialAudits) {.error.}
  ## An exact worker and its dependent transport owner cannot be copied.

proc `=dup`*(source: InitialAudits): InitialAudits {.error.}
  ## Duplicate ownership would bypass exact collection and cancellation.

proc `=wasMoved`*(owner: var InitialAudits) {.nodestroy, requires: not owner.working.} =
  ## The broadcast actor independently checks that all requests have retired.
  `=wasMoved`(owner.broadcast)
  `=wasMoved`(owner.ticket)
  `=wasMoved`(owner.declarations)
  `=wasMoved`(owner.prepared)

proc requireIdle(owner: InitialAudits) {.requires: not owner.working.} =
  ## An exact live worker must be collected or joined before dropping the actor.
  discard

proc `=destroy`*(owner: InitialAudits) =
  ## Stable node shutdown releases the worker before owned declarations.
  requireIdle(owner)
  `=destroy`(owner.broadcast)
  `=destroy`(owner.ticket)
  `=destroy`(owner.declarations)
  `=destroy`(owner.prepared)

proc configure*(owner: var InitialAudits, services: Services, streams: NodeService,
    policy: InitialAuditPolicy): bool =
  ## Both the actual node role and an explicitly installed signer are required.
  if owner.policy.ready or not policy.ready or not streams.isValidator or
      not services.hasTicketSigner:
    return false
  owner.policy = policy
  true

func declarationCount*(owner: InitialAudits): int =
  ## Count actual local declarations with nonempty selected obligations.
  owner.declarations.len

func readyDeclarationCount*(owner: InitialAudits): int =
  ## The newest declaration becomes actionable after bounded broadcast has completed.
  if owner.broadcast.sending: owner.declarations.len-1 else: owner.declarations.len

func declarationAt*(owner: InitialAudits, index: int): InitialAuditDeclaration {.requires:
    index >= 0 and index < owner.declarations.len.} =
  ## Return a fixed detached copy without exposing mutable queue storage.
  owner.declarations[index]

proc releaseDeclarationOrigin*(owner: var InitialAudits, services: var Services,
    index: int) {.requires: index >= 0 and index < owner.declarations.len.} =
  ## Keep the exact announcement for deduplication after releasing its execution state.
  let origin = owner.declarations[index].origin
  if origin.valid and services.releaseInitialAudit(origin):
    owner.declarations[index].origin = default(AuditOriginId)

proc advanceBlock(owner: var InitialAudits) =
  ## All original local positions on this block have been visited.
  if owner.side:
    owner.sideAfter = owner.sideSerial
    owner.side = false
  else: owner.afterSlot = owner.slot
  owner.ordinal = 0

func canExpire*(owner: InitialAudits): bool =
  ## Keep published and in-flight delivery stable until native fan-out retires.
  not owner.working and not owner.broadcast.sending

proc expireBefore*(owner: var InitialAudits, floor: uint64): seq[bool] {.requires:
    owner.canExpire.} =
  ## Return the exact old positions of survivors so execution retry state compacts with them.
  result = newSeq[bool](owner.declarations.len)
  owner.minimumEpoch = floor
  if owner.prepared.selected.count > 0 and owner.prepared.epoch < floor:
    owner.prepared = default(ProducedInitialAudit)
    owner.advanceBlock()
  var kept = 0
  for row in 0..<owner.declarations.len:
    # A survivor keeps its origin ID and exact original signing/report positions.
    if owner.declarations[row].epoch >= floor:
      result[row] = true
      if kept != row: owner.declarations[kept] = move(owner.declarations[row])
      inc kept
  owner.declarations.setLen(kept)

proc selectCanonical(owner: var InitialAudits, services: Services): bool =
  ## Select the next retained block by ascending slot without borrowing a graph across admission.
  let view = services.chainView
  var low = 0
  var high = view.retainedCount
  while low < high:
    # Retained canonical history is strictly ordered by slot.
    let middle = low+(high-low) div 2
    let retained = view.retainedBlockAt(RetainedBlockIndex(middle)).value
    if retained.slot <= owner.afterSlot: low = middle+1
    else: high = middle
  if low == view.retainedCount: return false
  let next = view.retainedBlockAt(RetainedBlockIndex(low)).value
  if next.slot != owner.slot or array[32, byte](next.blockHash) != array[32, byte](owner.blockHash):
    owner.slot = next.slot
    owner.blockHash = next.blockHash
    owner.ordinal = 0
  true

proc selectNext(owner: var InitialAudits, services: Services): bool =
  ## Alternate selected and side work, while retaining a started block's original ordinal cursor.
  if owner.side: return true
  if owner.ordinal > 0: return owner.selectCanonical(services)
  let candidate = services.nextAuditBranch(owner.sideAfter)
  if candidate.serial != 0 and (owner.preferSide or not owner.selectCanonical(services)):
    owner.side = true
    owner.preferSide = false
    owner.sideSerial = candidate.serial
    owner.blockHash = candidate.hash
    return true
  owner.preferSide = true
  owner.selectCanonical(services)

proc submit*(owner: var InitialAudits, services: var Services, streams: NodeService,
    clock: MonoTime): bool {.raises.} =
  ## The node arbitrates this optional work alongside incoming proof jobs.
  if not owner.policy.ready or owner.working or owner.broadcast.sending or
      owner.declarations.len >= owner.policy.maxDeclarations or clock < owner.retry:
    return false
  if not streams.isValidator or not services.stateProofAvailable or not services.hasTicketSigner:
    return false
  let pinning = owner.prepared.selected.count > 0
  if not pinning and not owner.selectNext(services): return false
  let started = if pinning:
      services.beginAuditOriginCapture(owner.blockHash, owner.policy.context, owner.policy.origin,
          forDeclaration = true)
    else:
      services.beginInitialAudit(owner.blockHash, streams.localIdentity,
          JudgeIndex(owner.ordinal), owner.policy.context, owner.policy.proof, discover = true)
  if started.error != StateProofAdmissionError.None:
    if owner.side and started.error == StateProofAdmissionError.QueryFailure:
      # The registered branch may have lost its independently finalized ancestor.
      owner.prepared = default(ProducedInitialAudit)
      owner.advanceBlock()
    return false
  owner.working = true
  owner.pinning = pinning
  owner.ticket = started.value
  true

func alreadyDeclared(owner: InitialAudits, record: AuditAnnouncement): bool =
  ## An independently retained side child may later become selected without creating a second declaration.
  for declaration in owner.declarations:
    let old = declaration.record
    if array[32, byte](old.header) == array[32, byte](record.header) and
        uint16(old.validator) == uint16(record.validator): return true
  false

proc poll*(owner: var InitialAudits, services: var Services, streams: var NodeService,
    clock: MonoTime) =
  ## Retain declared intent before sending so a completed or failed native attempt cannot erase it.
  if not owner.policy.ready: return
  owner.broadcast.poll(streams, clock)
  if not owner.working: return
  if not services.stateProofActive(owner.ticket):
    owner.working = false
    return
  if owner.pinning:
    let retained = services.collectAudit(owner.ticket)
    if retained.kind == ManagedAuditKind.Uninitialized: return
    owner.working = false
    owner.pinning = false
    owner.ticket = default(ProofWorkerTicket)
    if retained.kind == ManagedAuditKind.OriginRetained:
      let produced = move(owner.prepared)
      owner.prepared = default(ProducedInitialAudit)
      owner.declarations.add(InitialAuditDeclaration(record: produced.announcement,
          selected: produced.selected, reportOrdinals: produced.reportOrdinals,
          origin: retained.originId, epoch: produced.epoch))
      discard owner.broadcast.begin(produced, owner.policy.attempts, owner.policy.timeout,
          owner.policy.retry)
    elif retained.kind == ManagedAuditKind.OriginFailure and
        retained.originError.error == AuditOriginError.ContextFailure and
        retained.originError.contextError.error in [AuditContextError.UnknownBlock,
          AuditContextError.MissingBody, AuditContextError.MissingParent]:
      owner.prepared = default(ProducedInitialAudit)
      owner.advanceBlock()
    else:
      owner.retry = clock+initDuration(milliseconds = owner.policy.retry)
    return
  let done = services.collectStateProof(owner.ticket)
  if done.kind == ProofWorkerCompletionKind.Uninitialized: return
  owner.working = false
  owner.ticket = default(ProofWorkerTicket)
  if done.kind != ProofWorkerCompletionKind.WorkSubmitted:
    owner.retry = clock+initDuration(milliseconds = owner.policy.retry)
    return
  let outcome = done.workSubmissionValue
  case outcome.kind
  of WorkJobResultKind.InitialAuditProduced:
    let produced = outcome.producedInitialAudit
    owner.ordinal = uint16(produced.announcement.validator)+1
    if produced.epoch < owner.minimumEpoch: owner.advanceBlock()
    elif produced.selected.count > 0 and not owner.alreadyDeclared(produced.announcement):
      owner.prepared = produced
  of WorkJobResultKind.InitialAuditNoDuty:
    owner.advanceBlock()
  of WorkJobResultKind.InitialAuditSourceFailure:
    if outcome.initialAuditSourceError in [AuditContextError.UnknownBlock,
        AuditContextError.MissingBody, AuditContextError.MissingParent]:
      owner.advanceBlock()
    else:
      owner.retry = clock+initDuration(milliseconds = owner.policy.retry)
  else:
    owner.retry = clock+initDuration(milliseconds = owner.policy.retry)

proc close*(owner: var InitialAudits, services: var Services, streams: var NodeService) =
  ## Only the matching worker ticket grants permission to join a borrowed native source.
  if owner.working:
    if services.cancelStateProof(owner.ticket): services.stopStateProofs()
    elif owner.pinning:
      let completed = services.collectAudit(owner.ticket)
      if completed.kind == ManagedAuditKind.OriginRetained:
        services.retireInitialAudit(completed.originId)
  owner.working = false
  owner.ticket = default(ProofWorkerTicket)
  owner.broadcast.close(streams)
  for entry in owner.declarations: services.retireInitialAudit(entry.origin)
  owner.declarations = @[]
  owner.prepared = default(ProducedInitialAudit)
  owner.pinning = false
  owner.policy = default(InitialAuditPolicy)
  owner.afterSlot = 0
  owner.side = false
  owner.preferSide = false
  owner.sideAfter = 0
  owner.sideSerial = 0
  owner.minimumEpoch = 0
  owner.slot = 0
  owner.ordinal = 0
  owner.retry = default(MonoTime)
