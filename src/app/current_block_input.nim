# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Single-slot current raw-block reception with bounded copying and generation-safe callback retirement.
## Explicit preparation runs outside transport callbacks; only a current prepared update can reach adoption.

import ./chain as app_chain
import ./candidate as app_candidate
import ./current_handoff as app_current_handoff
import ../chain/genesis as chain_genesis
import ../chain/provider as chain_provider
import ../codec/bounded as codec_bounded
import ../codec/block_codec as codec_block_codec
import ../codec/header as codec_header
import ../state/store as state_store
import ../state/accumulation_current_update as state_accumulation_current_update
import ../state/report_admission as state_report_admission
import ../state/report_anchors as state_report_anchors

type
  CurrentBlockInputId* = distinct uint64 ## A local reception generation, never a peer/stream or block identity.
  CurrentBlockInputStage* {.pure.} = enum ## Ready retains exact raw bytes until explicit preparation or cancellation.
    Idle, Receiving, Ready, AwaitingAncestors
  CurrentBlockInputLimits* = object ## Explicit resource policy includes both payload storage and retained ancestor handles.
    blockBytes*, ancestorBytes*: ByteLimit
    ancestors*: ElementLimit
    discoverAncestors*: bool # Explicit opt-in; ordinary reception preserves its one-shot contract.
  CurrentBlockInputError* {.pure.} = enum ## Defaults and failures carry neither an admitted generation nor current prepared success.
    Uninitialized, None, Busy, MissingHead, ProfileMismatch, InvalidExtent, LimitExceeded,
    InvalidAncestor, Exhausted, StaleInput, NotReady, Truncated, StateChanged,
    DecodeFailure, TrailingBytes, PreparationFailure, EnqueueFailure, NeedsAncestors
  CurrentBlockInputAdmission* = object ## Only admitted reception exposes a callback generation.
    case status: CurrentBlockInputError
    of None:
      admitted: CurrentBlockInputId
    else:
      discard                          # Defaults/refusals have no usable callback identity.
  CurrentBlockInputResult* = object ## Current prepared success, explicit context demand or selected failure; prepared block storage never escapes.
    case status: CurrentBlockInputError
    of None:
      completed: PreparedCurrentChainUpdate
    of NeedsAncestors:
      demand: ReportLookupDemand
    of DecodeFailure:
      codecReason: FrameResult[BlockRead]
    of PreparationFailure:
      preparationReason: CurrentCandidateResult
    of EnqueueFailure:
      enqueueReason: CurrentHandoffAdmission
    else:
      discard # Identity/readiness/trailing failures retain no decoded owner.
  PendingCurrentBlockInput = object ## Private immutable context and fixed mutable byte storage live only in active alternatives.
    case status: CurrentBlockInputStage
    of Receiving, Ready, AwaitingAncestors:
      id: CurrentBlockInputId
      original: ApplicationChain
      policies: CurrentCandidateLimits
      ancestors: seq[OwnedHeader]
      wire: seq[byte]
      received: int
      resources: CurrentBlockInputLimits
      reports: PreparedCurrentCandidateReports
      demand: ReportLookupDemand
    else:
      discard # Idle retains no map, ancestor or byte owner.
  CurrentBlockInput* = object ## One mutable receiver; cancellation never resets its generation counter.
    next: uint64
    pending: PendingCurrentBlockInput

proc `=copy`*(destination: var CurrentBlockInput, source: CurrentBlockInput) {.error: "CurrentBlockInput owns mutable reception".}
proc `=dup`*(source: CurrentBlockInput): CurrentBlockInput {.error.}
  ## Duplication would share mutable reception and suspended-generation authority.
proc `==`*(left, right: CurrentBlockInputId): bool {.borrow.}
  ## Compare local generations without accepting integer or stream identities.

func stage*(input: CurrentBlockInput): CurrentBlockInputStage =
  ## Observe readiness without publishing mutable storage or the selected context.
  input.pending.status

func error*(outcome: CurrentBlockInputAdmission): CurrentBlockInputError =
  ## Observe admission without allowing retagging or forged generations.
  outcome.status

func value*(outcome: CurrentBlockInputAdmission): CurrentBlockInputId {.inline,
    requires: outcome.status == CurrentBlockInputError.None.} =
  ## Only successful admission authorizes callbacks for the retained slot.
  outcome.admitted

func error*(outcome: CurrentBlockInputResult): CurrentBlockInputError =
  ## Observe preparation status without extracting an unrelated child or success.
  outcome.status

func value*(outcome: CurrentBlockInputResult): PreparedCurrentChainUpdate {.inline,
    requires: outcome.status == CurrentBlockInputError.None.} =
  ## Extract only complete execution success; canonical adoption remains separate.
  outcome.completed

func decodeFailure*(outcome: CurrentBlockInputResult): FrameResult[BlockRead] {.inline,
    requires: outcome.status == CurrentBlockInputError.DecodeFailure.} =
  ## Preserve the failed codec's typed component cause without a usable decoded owner.
  outcome.codecReason

func preparationFailure*(outcome: CurrentBlockInputResult): CurrentCandidateResult {.inline,
    requires: outcome.status == CurrentBlockInputError.PreparationFailure.} =
  ## Preserve only the actual selected candidate failure, including its typed stage cause.
  outcome.preparationReason

func enqueueError*(outcome: CurrentBlockInputResult): CurrentHandoffAdmission {.inline,
    requires: outcome.status == CurrentBlockInputError.EnqueueFailure.} =
  ## Inspect only a selected handoff refusal; it contains no successful execution prefix.
  outcome.enqueueReason

func ancestorDemand*(outcome: CurrentBlockInputResult): ReportLookupDemand {.inline,
    requires: outcome.status == CurrentBlockInputError.NeedsAncestors.} =
  ## Extract only the actual certified discovery plan; it grants no current preparation or adoption authority.
  outcome.demand

proc begin*(input: var CurrentBlockInput, chain: ApplicationChain, extent: ByteLimit,
    ancestors: openArray[OwnedHeader], resources: CurrentBlockInputLimits,
    policies: CurrentCandidateLimits): CurrentBlockInputAdmission =
  ## Preflight all storage/profile limits before copying handles or allocating the exact payload extent.
  if input.stage != CurrentBlockInputStage.Idle:
    return CurrentBlockInputAdmission(status: CurrentBlockInputError.Busy) # Active input is never replaced by a new peer.
  let selected = chain.chainView.bestBlock
  if selected.error != GenesisError.None or chain.stateSnapshot.error != StateStoreError.None:
    return CurrentBlockInputAdmission(status: CurrentBlockInputError.MissingHead) # No implicit complete state or parent.
  let head = selected.value
  let frame = policies.reporting.admission.frame
  # GP valcount permits independent roster sizes; the decoder ceiling covers the head up to three validators per core.
  if uint64(frame.cores) != uint64(head.cores) or
      uint64(frame.validators) < uint64(head.activeValidators) or
      uint64(frame.validators) mod 3 != 0 or
      uint64(frame.validators) div 3 > uint64(head.cores) or
      uint64(frame.epochSlots) != uint64(head.epochSlots):
    return CurrentBlockInputAdmission(status: CurrentBlockInputError.ProfileMismatch) # Domain refusal does no hashing/decoding.
  let size = uint64(extent)
  if size == 0 or size > uint64(high(int)):
    return CurrentBlockInputAdmission(status: CurrentBlockInputError.InvalidExtent) # Prove host conversion before allocation.
  if size > uint64(resources.blockBytes) or size > uint64(frame.maxBytes) or
      uint64(ancestors.len) > uint64(resources.ancestors) or ancestors.len > high(int) div sizeof(OwnedHeader):
    return CurrentBlockInputAdmission(status: CurrentBlockInputError.LimitExceeded) # Neither sender size nor ancestor count widens policy.
  var remaining = uint64(resources.ancestorBytes)
  for ancestor in ancestors:
    let info = ancestor.headerInfo
    if info.error != HeaderError.None:
      return CurrentBlockInputAdmission(status: CurrentBlockInputError.InvalidAncestor) # Defaults cannot occupy trusted history context.
    let bytes = uint64(info.value.consumed)
    if bytes > remaining:
      return CurrentBlockInputAdmission(status: CurrentBlockInputError.LimitExceeded) # Subtraction avoids cumulative-length overflow.
    remaining -= bytes
  if input.next == high(uint64):
    return CurrentBlockInputAdmission(status: CurrentBlockInputError.Exhausted) # No generation reuse through wraparound.
  var retained = newSeq[OwnedHeader](ancestors.len)
  for index, ancestor in ancestors: retained[index] = ancestor # Retain immutable handles, never caller's sequence backing.
  inc input.next
  let id = CurrentBlockInputId(input.next)
  input.pending = PendingCurrentBlockInput(status: CurrentBlockInputStage.Receiving, id: id,
    original: chain, policies: policies, ancestors: retained, wire: newSeq[byte](int(size)),
        received: 0, resources: resources)
  CurrentBlockInputAdmission(status: CurrentBlockInputError.None, admitted: id)

proc append*(input: var CurrentBlockInput, id: CurrentBlockInputId, fragment: openArray[byte],
    final: bool): CurrentBlockInputError =
  ## Copy only within the admitted extent; local final means the enclosing payload has ended, not a new wire protocol.
  if input.stage == CurrentBlockInputStage.Idle or input.pending.id != id:
    return CurrentBlockInputError.StaleInput # Late callbacks cannot write into another reception.
  if input.stage != CurrentBlockInputStage.Receiving:
    return CurrentBlockInputError.Busy # Ready bytes cannot be extended or replaced before explicit consumption.
  let remaining = input.pending.wire.len - input.pending.received
  if fragment.len > remaining:
    input.pending = default(PendingCurrentBlockInput)
    return CurrentBlockInputError.LimitExceeded # Overlong input retires all partial bytes before any write.
  for index, octet in fragment:
    input.pending.wire[input.pending.received + index] = octet # Bounds were proved before addition/indexing.
  input.pending.received += fragment.len
  if final:
    if input.pending.received != input.pending.wire.len:
      input.pending = default(PendingCurrentBlockInput)
      return CurrentBlockInputError.Truncated # Early termination cannot authorize a valid-prefix block.
    input.pending.status = CurrentBlockInputStage.Ready # Both active alternatives have identical owned fields.
  CurrentBlockInputError.None

proc cancel*(input: var CurrentBlockInput, id: CurrentBlockInputId): bool =
  ## Retire only the identified active reception, retaining the monotonic counter for subsequent callbacks.
  if input.stage == CurrentBlockInputStage.Idle or input.pending.id !=
      id: return false # Stale cancellation is inert.
  input.pending = default(PendingCurrentBlockInput)
  true

proc prepare*(input: var CurrentBlockInput, id: CurrentBlockInputId,
    chain: ApplicationChain): CurrentBlockInputResult =
  ## Consume Ready once outside transport callbacks; terminal failures release raw storage just like success.
  if input.stage == CurrentBlockInputStage.Idle or input.pending.id != id:
    return CurrentBlockInputResult(status: CurrentBlockInputError.StaleInput) # No other generation is consumed.
  if input.stage != CurrentBlockInputStage.Ready:
    return CurrentBlockInputResult(status: CurrentBlockInputError.NotReady) # Incomplete bytes remain available for continuation.
  var pending = move(input.pending)
  input.pending = default(PendingCurrentBlockInput) # Every terminal path releases this slot and its retained source context.
  if not sameChainView(pending.original.chainView, chain.chainView):
    return CurrentBlockInputResult(status: CurrentBlockInputError.StateChanged) # Do not execute work against a substituted/currently different parent.
  var reports = pending.reports
  if not reports.ready:
    let decoded = decodeBlock(pending.wire, pending.policies.reporting.admission.frame)
    if decoded.error != FrameError.None:
      return CurrentBlockInputResult(status: CurrentBlockInputError.DecodeFailure,
          codecReason: decoded)
    if decoded.value.consumed != pending.wire.len:
      return CurrentBlockInputResult(status: CurrentBlockInputError.TrailingBytes) # Input remains exactly one full block, including on discovery paths.
    if not pending.resources.discoverAncestors:
      let prepared = prepareCurrentCandidate(chain, decoded.value.owner, pending.ancestors,
          pending.policies)
      if prepared.error != CurrentCandidateError.None:
        return CurrentBlockInputResult(status: CurrentBlockInputError.PreparationFailure,
            preparationReason: prepared)
      return CurrentBlockInputResult(status: CurrentBlockInputError.None, completed: prepared.value)
    let prepared = prepareCurrentCandidateReports(chain, decoded.value.owner, pending.policies)
    if prepared.error != CurrentCandidateError.None:
      return CurrentBlockInputResult(status: CurrentBlockInputError.PreparationFailure,
          preparationReason: prepared.failure)
    reports = prepared.value # The original block/signatures/state stages will never run again for this input.
  let needed = reports.currentCandidateLookupDemand(pending.ancestors)
  if needed.error == ReportAdmissionError.None and needed.value.missingLookups.value > 0:
    pending.status = CurrentBlockInputStage.AwaitingAncestors
    pending.reports = reports
    pending.demand = needed.value
    pending.wire = @[] # The opaque prepared block owns exact original provenance; redundant raw bytes can retire now.
    pending.received = 0
    input.pending = move(pending)
    return CurrentBlockInputResult(status: CurrentBlockInputError.NeedsAncestors,
        demand: needed.value)
  let prepared = completeCurrentCandidateReports(chain, reports, pending.ancestors)
  if prepared.error != CurrentCandidateError.None:
    return CurrentBlockInputResult(status: CurrentBlockInputError.PreparationFailure,
        preparationReason: prepared)
  CurrentBlockInputResult(status: CurrentBlockInputError.None, completed: prepared.value)

proc resumeAncestors*(input: var CurrentBlockInput, id: CurrentBlockInputId,
    chain: ApplicationChain, ancestors: openArray[OwnedHeader]): CurrentBlockInputError =
  ## Replace context only after worker collection; preserve the original prepared block and generation on quota refusal.
  if input.stage == CurrentBlockInputStage.Idle or input.pending.id !=
      id: return CurrentBlockInputError.StaleInput
  if input.stage != CurrentBlockInputStage.AwaitingAncestors: return CurrentBlockInputError.NotReady
  if not sameChainView(input.pending.original.chainView,
      chain.chainView): return CurrentBlockInputError.StateChanged
  let resources = input.pending.resources
  if uint64(ancestors.len) > uint64(resources.ancestors) or ancestors.len > high(int) div sizeof(
      OwnedHeader): return CurrentBlockInputError.LimitExceeded
  var remaining = uint64(resources.ancestorBytes)
  for owner in ancestors:
    # Preflight every immutable input before allocating a replacement sequence; no hashing or guest work occurs here.
    let info = owner.headerInfo
    if info.error != HeaderError.None: return CurrentBlockInputError.InvalidAncestor
    if uint64(info.value.consumed) > remaining: return CurrentBlockInputError.LimitExceeded
    remaining -= uint64(info.value.consumed)
  var retained = newSeq[OwnedHeader](ancestors.len)
  for index, owner in ancestors: retained[index] = owner # Caller sequence replacement cannot alter the suspended source.
  input.pending.ancestors = retained
  input.pending.demand = default(ReportLookupDemand)
  input.pending.status = CurrentBlockInputStage.Ready # Only a later explicit preparation turn may complete lookup proofs and execute.
  CurrentBlockInputError.None

proc enqueue*(input: var CurrentBlockInput, id: CurrentBlockInputId, chain: ApplicationChain,
    handoff: var CurrentAccumulationHandoff): CurrentBlockInputResult =
  ## Producer-only synchronous preparation checks handoff backpressure first; dispatcher ticks still only adopt.
  if handoff.phase != CurrentHandoffPhase.Idle:
    return CurrentBlockInputResult(status: CurrentBlockInputError.Busy) # Keep Ready input for retry without decoding or hashing.
  let prepared = input.prepare(id, chain)
  if prepared.error != CurrentBlockInputError.None: return prepared # Terminal preparation already retired raw bytes.
  let admitted = handoff.enqueue(chain, prepared.value)
  if admitted != CurrentHandoffAdmission.None:
    return CurrentBlockInputResult(status: CurrentBlockInputError.EnqueueFailure,
        enqueueReason: admitted)
  prepared
