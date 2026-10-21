# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Single-slot raw-block reception with bounded copying and generation-safe callback retirement.
## Explicit preparation runs outside transport callbacks; only finalized success can reach adoption.

import ./[chain, candidate, handoff]
import ../chain/[genesis, provider]
import ../codec/[bounded, block_codec, header]
import ../state/[store, accumulation_finalization, accumulation_completion, report_admission, report_anchors]

type
  BlockInputId* = distinct uint64 ## A local reception generation, never a peer/stream or block identity.
  BlockInputStage* {.pure.} = enum ## Ready retains exact raw bytes until explicit preparation or cancellation.
    Idle, Receiving, Ready, AwaitingAncestors
  BlockInputLimits* = object ## Explicit resource policy includes both payload storage and retained ancestor handles.
    blockBytes*, ancestorBytes*: ByteLimit
    ancestors*: ElementLimit
    discoverAncestors*: bool # Explicit opt-in; ordinary reception preserves its one-shot contract.
  BlockInputError* {.pure.} = enum ## Defaults and failures carry neither an admitted generation nor finalized success.
    Uninitialized, None, Busy, MissingHead, ProfileMismatch, InvalidExtent, LimitExceeded,
    InvalidAncestor, Exhausted, StaleInput, NotReady, Truncated, StateChanged,
    DecodeFailure, TrailingBytes, PreparationFailure, EnqueueFailure, NeedsAncestors
  BlockInputAdmission* = object ## Only admitted reception exposes a callback generation.
    case status: BlockInputError
    of None:
      admitted: BlockInputId
    else:
      discard                   # Defaults/refusals have no usable callback identity.
  BlockInputResult* = object ## Finalized success, explicit context demand or selected failure; prepared block storage never escapes.
    case status: BlockInputError
    of None:
      completed: PreparedFinalAccumulation
    of NeedsAncestors:
      demand: ReportLookupDemand
    of DecodeFailure:
      codecReason: FrameResult[BlockRead]
    of PreparationFailure:
      preparationReason: ApplicationCandidateResult
    of EnqueueFailure:
      enqueueReason: AccumulationEnqueueError
    else:
      discard # Identity/readiness/trailing failures retain no decoded owner.
  PendingBlockInput = object ## Private immutable context and fixed mutable byte storage live only in active alternatives.
    case status: BlockInputStage
    of Receiving, Ready, AwaitingAncestors:
      id: BlockInputId
      original: ApplicationChain
      policies: ApplicationCandidateLimits
      ancestors: seq[OwnedHeader]
      wire: seq[byte]
      received: int
      resources: BlockInputLimits
      reports: PreparedCandidateReports
      demand: ReportLookupDemand
    else:
      discard # Idle retains no map, ancestor or byte owner.
  BlockInput* = object ## One mutable receiver; cancellation never resets its generation counter.
    next: uint64
    pending: PendingBlockInput

proc `=copy`*(destination: var BlockInput, source: BlockInput) {.error: "BlockInput owns mutable reception".}
proc `=dup`*(source: BlockInput): BlockInput {.error.}
  ## Duplication would share mutable reception and suspended-generation authority.
proc `==`*(left, right: BlockInputId): bool {.borrow.}
  ## Compare local generations without accepting integer or stream identities.

func stage*(input: BlockInput): BlockInputStage =
  ## Observe readiness without publishing mutable storage or the selected context.
  input.pending.status

func error*(outcome: BlockInputAdmission): BlockInputError =
  ## Observe admission without allowing retagging or forged generations.
  outcome.status

func value*(outcome: BlockInputAdmission): BlockInputId {.inline,
    requires: outcome.status == BlockInputError.None.} =
  ## Only successful admission authorizes callbacks for the retained slot.
  outcome.admitted

func error*(outcome: BlockInputResult): BlockInputError =
  ## Observe preparation status without extracting an unrelated child or success.
  outcome.status

func value*(outcome: BlockInputResult): PreparedFinalAccumulation {.inline,
    requires: outcome.status == BlockInputError.None.} =
  ## Extract only complete execution success; canonical adoption remains separate.
  outcome.completed

func decodeFailure*(outcome: BlockInputResult): FrameResult[BlockRead] {.inline,
    requires: outcome.status == BlockInputError.DecodeFailure.} =
  ## Preserve the failed codec's typed component cause without a usable decoded owner.
  outcome.codecReason

func preparationFailure*(outcome: BlockInputResult): ApplicationCandidateResult {.inline,
    requires: outcome.status == BlockInputError.PreparationFailure.} =
  ## Preserve only the actual selected candidate failure, including its typed stage cause.
  outcome.preparationReason

func enqueueError*(outcome: BlockInputResult): AccumulationEnqueueError {.inline,
    requires: outcome.status == BlockInputError.EnqueueFailure.} =
  ## Inspect only a selected handoff refusal; it contains no successful execution prefix.
  outcome.enqueueReason

func ancestorDemand*(outcome: BlockInputResult): ReportLookupDemand {.inline,
    requires: outcome.status == BlockInputError.NeedsAncestors.} =
  ## Extract only the actual certified discovery plan; it grants no finalization or adoption authority.
  outcome.demand

proc begin*(input: var BlockInput, chain: ApplicationChain, extent: ByteLimit,
    ancestors: openArray[OwnedHeader], resources: BlockInputLimits,
    policies: ApplicationCandidateLimits): BlockInputAdmission =
  ## Preflight all storage/profile limits before copying handles or allocating the exact payload extent.
  if input.stage != BlockInputStage.Idle:
    return BlockInputAdmission(status: BlockInputError.Busy) # Active input is never replaced by a new peer.
  let selected = chain.chainView.bestBlock
  if selected.error != GenesisError.None or chain.stateSnapshot.error != StateStoreError.None:
    return BlockInputAdmission(status: BlockInputError.MissingHead) # No implicit complete state or parent.
  let head = selected.value
  let frame = policies.reporting.admission.frame
  if uint64(frame.cores) != uint64(head.cores) or
      uint64(frame.validators) != uint64(head.activeValidators) or
      uint64(frame.epochSlots) != uint64(head.epochSlots):
    return BlockInputAdmission(status: BlockInputError.ProfileMismatch) # Domain refusal does no hashing/decoding.
  let size = uint64(extent)
  if size == 0 or size > uint64(high(int)):
    return BlockInputAdmission(status: BlockInputError.InvalidExtent) # Prove host conversion before allocation.
  if size > uint64(resources.blockBytes) or size > uint64(frame.maxBytes) or
      uint64(ancestors.len) > uint64(resources.ancestors) or ancestors.len > high(int) div sizeof(OwnedHeader):
    return BlockInputAdmission(status: BlockInputError.LimitExceeded) # Neither sender size nor ancestor count widens policy.
  var remaining = uint64(resources.ancestorBytes)
  for ancestor in ancestors:
    let info = ancestor.headerInfo
    if info.error != HeaderError.None:
      return BlockInputAdmission(status: BlockInputError.InvalidAncestor) # Defaults cannot occupy trusted history context.
    let bytes = uint64(info.value.consumed)
    if bytes > remaining:
      return BlockInputAdmission(status: BlockInputError.LimitExceeded) # Subtraction avoids cumulative-length overflow.
    remaining -= bytes
  if input.next == high(uint64):
    return BlockInputAdmission(status: BlockInputError.Exhausted) # No generation reuse through wraparound.
  var retained = newSeq[OwnedHeader](ancestors.len)
  for index, ancestor in ancestors: retained[index] = ancestor # Retain immutable handles, never caller's sequence backing.
  inc input.next
  let id = BlockInputId(input.next)
  input.pending = PendingBlockInput(status: BlockInputStage.Receiving, id: id,
    original: chain, policies: policies, ancestors: retained, wire: newSeq[byte](int(size)),
        received: 0, resources: resources)
  BlockInputAdmission(status: BlockInputError.None, admitted: id)

proc append*(input: var BlockInput, id: BlockInputId, fragment: openArray[byte],
    final: bool): BlockInputError =
  ## Copy only within the admitted extent; local final means the enclosing payload has ended, not a new wire protocol.
  if input.stage == BlockInputStage.Idle or input.pending.id != id:
    return BlockInputError.StaleInput # Late callbacks cannot write into another reception.
  if input.stage != BlockInputStage.Receiving:
    return BlockInputError.Busy # Ready bytes cannot be extended or replaced before explicit consumption.
  let remaining = input.pending.wire.len - input.pending.received
  if fragment.len > remaining:
    input.pending = default(PendingBlockInput)
    return BlockInputError.LimitExceeded # Overlong input retires all partial bytes before any write.
  for index, octet in fragment:
    input.pending.wire[input.pending.received + index] = octet # Bounds were proved before addition/indexing.
  input.pending.received += fragment.len
  if final:
    if input.pending.received != input.pending.wire.len:
      input.pending = default(PendingBlockInput)
      return BlockInputError.Truncated # Early termination cannot authorize a valid-prefix block.
    input.pending.status = BlockInputStage.Ready # Both active alternatives have identical owned fields.
  BlockInputError.None

proc cancel*(input: var BlockInput, id: BlockInputId): bool =
  ## Retire only the identified active reception, retaining the monotonic counter for subsequent callbacks.
  if input.stage == BlockInputStage.Idle or input.pending.id != id: return false # Stale cancellation is inert.
  input.pending = default(PendingBlockInput)
  true

proc prepare*(input: var BlockInput, id: BlockInputId,
    chain: ApplicationChain): BlockInputResult =
  ## Consume Ready once outside transport callbacks; terminal failures release raw storage just like success.
  if input.stage == BlockInputStage.Idle or input.pending.id != id:
    return BlockInputResult(status: BlockInputError.StaleInput) # No other generation is consumed.
  if input.stage != BlockInputStage.Ready:
    return BlockInputResult(status: BlockInputError.NotReady) # Incomplete bytes remain available for continuation.
  var pending = move(input.pending)
  input.pending = default(PendingBlockInput) # Every terminal path releases this slot and its retained source context.
  if not sameChainView(pending.original.chainView, chain.chainView):
    return BlockInputResult(status: BlockInputError.StateChanged) # Do not execute work against a substituted/currently different parent.
  var reports = pending.reports
  if not reports.valid:
    let decoded = decodeBlock(pending.wire, pending.policies.reporting.admission.frame)
    if decoded.error != FrameError.None:
      return BlockInputResult(status: BlockInputError.DecodeFailure, codecReason: decoded)
    if decoded.value.consumed != pending.wire.len:
      return BlockInputResult(status: BlockInputError.TrailingBytes) # Input remains exactly one full block, including on discovery paths.
    if not pending.resources.discoverAncestors:
      let prepared = prepareCandidate(chain, decoded.value.owner, pending.ancestors,
          pending.policies)
      if prepared.error != ApplicationCandidateError.None:
        return BlockInputResult(status: BlockInputError.PreparationFailure,
            preparationReason: prepared)
      return BlockInputResult(status: BlockInputError.None, completed: prepared.value)
    let prepared = prepareCandidateReports(chain, decoded.value.owner, pending.policies)
    if prepared.error != ApplicationCandidateError.None:
      return BlockInputResult(status: BlockInputError.PreparationFailure,
          preparationReason: prepared.failure)
    reports = prepared.value # The original block/signatures/state stages will never run again for this input.
  let needed = reports.candidateLookupDemand(pending.ancestors)
  if needed.error == ReportAdmissionError.None and needed.value.missingLookups.value > 0:
    pending.status = BlockInputStage.AwaitingAncestors
    pending.reports = reports
    pending.demand = needed.value
    pending.wire = @[] # The opaque prepared block owns exact original provenance; redundant raw bytes can retire now.
    pending.received = 0
    input.pending = move(pending)
    return BlockInputResult(status: BlockInputError.NeedsAncestors, demand: needed.value)
  let prepared = completeCandidateReports(chain, reports, pending.ancestors)
  if prepared.error != ApplicationCandidateError.None:
    return BlockInputResult(status: BlockInputError.PreparationFailure, preparationReason: prepared)
  BlockInputResult(status: BlockInputError.None, completed: prepared.value)

proc resumeAncestors*(input: var BlockInput, id: BlockInputId, chain: ApplicationChain,
    ancestors: openArray[OwnedHeader]): BlockInputError =
  ## Replace context only after worker collection; preserve the original prepared block and generation on quota refusal.
  if input.stage == BlockInputStage.Idle or input.pending.id !=
      id: return BlockInputError.StaleInput
  if input.stage != BlockInputStage.AwaitingAncestors: return BlockInputError.NotReady
  if not sameChainView(input.pending.original.chainView,
      chain.chainView): return BlockInputError.StateChanged
  let resources = input.pending.resources
  if uint64(ancestors.len) > uint64(resources.ancestors) or ancestors.len > high(int) div sizeof(
      OwnedHeader): return BlockInputError.LimitExceeded
  var remaining = uint64(resources.ancestorBytes)
  for owner in ancestors:
    # Preflight every immutable input before allocating a replacement sequence; no hashing or guest work occurs here.
    let info = owner.headerInfo
    if info.error != HeaderError.None: return BlockInputError.InvalidAncestor
    if uint64(info.value.consumed) > remaining: return BlockInputError.LimitExceeded
    remaining -= uint64(info.value.consumed)
  var retained = newSeq[OwnedHeader](ancestors.len)
  for index, owner in ancestors: retained[index] = owner # Caller sequence replacement cannot alter the suspended source.
  input.pending.ancestors = retained
  input.pending.demand = default(ReportLookupDemand)
  input.pending.status = BlockInputStage.Ready # Only a later explicit preparation turn may complete lookup proofs and execute.
  BlockInputError.None

proc enqueue*(input: var BlockInput, id: BlockInputId, chain: ApplicationChain,
    handoff: var AccumulationHandoff, composition: AccumulationCompositionLimits): BlockInputResult =
  ## Producer-only synchronous preparation checks handoff backpressure first; dispatcher ticks still only adopt.
  if handoff.stage != AccumulationHandoffStage.Idle:
    return BlockInputResult(status: BlockInputError.Busy) # Keep Ready input for retry without decoding or hashing.
  let prepared = input.prepare(id, chain)
  if prepared.error != BlockInputError.None: return prepared # Terminal preparation already retired raw bytes.
  let admitted = handoff.enqueue(chain, prepared.value, composition)
  if admitted != AccumulationEnqueueError.None:
    return BlockInputResult(status: BlockInputError.EnqueueFailure, enqueueReason: admitted)
  prepared
