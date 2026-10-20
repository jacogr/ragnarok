# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CE 128 one-child request and bounded incremental response adapter over the existing raw-block input owner.
## Native callbacks copy bytes/observe FIN; explicit producer enqueue performs validation and PVM work later.

import ./[chain, candidate, block_input, services, handoff]
import ../chain/[genesis, provider]
import ../codec/[bounded, header]
import ../state/[store, accumulation_finalization, accumulation_completion]

type
  BlockDownloadId* = distinct uint64 ## Local receiver generations are unrelated to QUIC handles and block identities.
  BlockDownloadStage* {.pure.} = enum ## Terminal empty/failure outcomes remain observable until explicit acknowledgement.
    Idle, Receiving, Ready, Empty, Failed
  BlockDownloadError* {.pure.} = enum ## Successful framing is distinct from a usable finalized successor.
    Uninitialized, None, Busy, MissingHead, ProfileMismatch, LimitExceeded, InvalidAncestor,
    Exhausted, StaleDownload, NotReady, Truncated, Trailing, EmptyResponse, InputFailure,
    PreparationFailure
  BlockDownloadFailure* = object ## Only the actual selected failed child is retained; no successful prefix survives refusal.
    case status: BlockDownloadError
    of InputFailure:
      inputReason: BlockInputError
    of PreparationFailure:
      preparationReason: BlockInputResult
    else:
      discard # Plain framing/readiness reasons retain no child owners.
  BlockDownloadResult*[T] = object ## Defaults are failures; only checked success authorizes generation/request/certificate access.
    case successful: bool
    of true:
      completed: T
    else:
      refused: BlockDownloadFailure
  PendingDownload = object ## Native stream ownership remains with the caller; this context retains only immutable application handles.
    id: BlockDownloadId
    case status: BlockDownloadStage
    of Receiving, Ready:
      original: ApplicationChain
      ancestors: seq[OwnedHeader]
      resources: BlockInputLimits
      policies: ApplicationCandidateLimits
      request: array[42, byte]
      header: array[4, byte]
      headerBytes, claimed, received: int
      headerDone, requestFin, responseFin: bool
      inputId: BlockInputId
    of Failed:
      refusal: BlockDownloadFailure
    else:
      discard # Idle/Empty retain neither payload nor canonical context.
  BlockDownload* = object ## One producer/callback owner; the nested input's mutable bytes must never be copied.
    next: uint64
    pending: PendingDownload
    input: BlockInput

proc `=copy`*(destination: var BlockDownload, source: BlockDownload) {.error: "BlockDownload owns reception".}
  ## Composite ownership is explicit even though BlockInput already refuses copying.
proc `==`*(left, right: BlockDownloadId): bool {.borrow.}
  ## Compare only generations from this receiver's lifetime.

func stage*(download: BlockDownload): BlockDownloadStage =
  ## Observe readiness independently of the caller's still-live native stream handle.
  download.pending.status

func error*(reason: BlockDownloadFailure): BlockDownloadError =
  ## Inspect only the selected reason without allowing external retagging.
  reason.status

func error*[T](outcome: BlockDownloadResult[T]): BlockDownloadError =
  ## Defaults/refusals cannot masquerade as admitted generations or finalized success.
  if outcome.successful: BlockDownloadError.None
  else: outcome.refused.error # Failure has no usable generic payload.

func value*[T](outcome: BlockDownloadResult[T]): T {.inline, requires: outcome.successful.} =
  ## Extract only after selecting successful admission/request/preparation.
  outcome.completed

func failure*[T](outcome: BlockDownloadResult[T]): BlockDownloadFailure {.inline,
    requires: not outcome.successful.} =
  ## Inspect only an actual refused result, never an invented reason for success.
  outcome.refused

func failure*(download: BlockDownload): BlockDownloadFailure {.inline,
    requires: download.stage == BlockDownloadStage.Failed.} =
  ## Native consumers may acknowledge a retained framing/preparation failure after retiring the stream.
  download.pending.refusal

func inputError*(reason: BlockDownloadFailure): BlockInputError {.inline,
    requires: reason.status == BlockDownloadError.InputFailure.} =
  ## Inspect only the selected raw-input admission/reception error.
  reason.inputReason

func preparationFailure*(reason: BlockDownloadFailure): BlockInputResult {.inline,
    requires: reason.status == BlockDownloadError.PreparationFailure.} =
  ## Preserve only the actual failed preparation child, including codec/stage-specific diagnostics.
  reason.preparationReason

func refused[T](reason: BlockDownloadError): BlockDownloadResult[T] =
  ## Construct a plain refusal without a successful payload or unrelated child error.
  BlockDownloadResult[T](successful: false, refused: BlockDownloadFailure(status: reason))

proc fail(download: var BlockDownload, reason: BlockDownloadFailure): BlockDownloadError =
  ## Retire every partial raw/context owner while retaining only the selected failure and callback identity.
  let id = download.pending.id
  if download.input.stage != BlockInputStage.Idle:
    discard download.input.cancel(download.pending.inputId) # Only this receiver can own the nested generation.
  download.pending = PendingDownload(status: BlockDownloadStage.Failed, id: id, refusal: reason)
  reason.error

proc begin*(download: var BlockDownload, chain: ApplicationChain,
    ancestors: openArray[OwnedHeader], resources: BlockInputLimits,
    policies: ApplicationCandidateLimits): BlockDownloadResult[BlockDownloadId] =
  ## Bound retained context before any request is emitted; the exact response extent arrives later in its E4 header.
  if download.stage != BlockDownloadStage.Idle:
    return refused[BlockDownloadId](BlockDownloadError.Busy) # Terminal outcomes also require acknowledgement.
  let selected = chain.chainView.bestBlock
  if selected.error != GenesisError.None or chain.stateSnapshot.error != StateStoreError.None:
    return refused[BlockDownloadId](BlockDownloadError.MissingHead) # No implicit requested hash or complete map.
  let head = selected.value
  let frame = policies.reporting.admission.frame
  if uint64(frame.cores) != uint64(head.cores) or
      uint64(frame.validators) != uint64(head.activeValidators) or
      uint64(frame.epochSlots) != uint64(head.epochSlots):
    return refused[BlockDownloadId](BlockDownloadError.ProfileMismatch) # Refuse unrelated profile without hashing.
  if uint64(resources.blockBytes) == 0 or uint64(frame.maxBytes) == 0 or
      uint64(ancestors.len) > uint64(resources.ancestors):
    return refused[BlockDownloadId](BlockDownloadError.LimitExceeded) # Context retention has its own preflight before response framing.
  var remaining = uint64(resources.ancestorBytes)
  for ancestor in ancestors:
    let info = ancestor.headerInfo
    if info.error != HeaderError.None:
      return refused[BlockDownloadId](BlockDownloadError.InvalidAncestor) # Never retain a default header as context.
    if uint64(info.value.consumed) > remaining:
      return refused[BlockDownloadId](BlockDownloadError.LimitExceeded) # Prove cumulative bytes by subtraction.
    remaining -= uint64(info.value.consumed)
  if download.next == high(uint64):
    return refused[BlockDownloadId](BlockDownloadError.Exhausted) # A late callback never sees a wrapped generation.
  var retained = newSeq[OwnedHeader](ancestors.len)
  for index, ancestor in ancestors: retained[index] = ancestor # Retain handles independently of caller sequence backing.
  var request = default(array[42, byte])
  request[0] = 128
  request[1] = 37
  for index, octet in array[32, byte](head.blockHash): request[5 +
      index] = octet # The captured head alone supplies the start hash.
  request[38] = 1 # Direction zero and E4 maximum one; all other fixed bytes were initialized to zero.
  inc download.next
  let id = BlockDownloadId(download.next)
  download.pending = PendingDownload(status: BlockDownloadStage.Receiving, id: id,
    original: chain, ancestors: retained, resources: resources, policies: policies,
    request: request, header: default(array[4, byte]), headerBytes: 0, claimed: 0, received: 0,
    headerDone: false, requestFin: false, responseFin: false, inputId: default(BlockInputId))
  BlockDownloadResult[BlockDownloadId](successful: true, completed: id)

proc begin*(download: var BlockDownload, owner: Services, ancestors: openArray[OwnedHeader],
    resources: BlockInputLimits, policies: ApplicationCandidateLimits): BlockDownloadResult[
        BlockDownloadId] =
  ## Select the service's immutable canonical history without exposing its mutable ApplicationChain owner.
  let chain = initApplicationChain(owner.chainView)
  if chain.error != ApplicationChainError.None:
    return refused[BlockDownloadId](BlockDownloadError.MissingHead) # Closed/default services have no requested head.
  download.begin(chain.value, ancestors, resources, policies)

proc request*(download: BlockDownload, id: BlockDownloadId): BlockDownloadResult[array[42, byte]] =
  ## Copy the complete fixed request; callers own partial-write offsets and queue FIN only after all 42 bytes.
  if download.stage notin [BlockDownloadStage.Receiving, BlockDownloadStage.Ready] or
      download.pending.id != id:
    return refused[array[42, byte]](BlockDownloadError.StaleDownload) # No request for a different/retired callback generation.
  BlockDownloadResult[array[42, byte]](successful: true, completed: download.pending.request)

proc finish(download: var BlockDownload) =
  ## Complete framing only when both stream directions ended cleanly; a valid empty sequence contains no candidate.
  if download.pending.requestFin and download.pending.responseFin:
    if download.pending.claimed == 0:
      download.pending = PendingDownload(status: BlockDownloadStage.Empty,
          id: download.pending.id) # Release captured history too.
    else:
      download.pending.status = BlockDownloadStage.Ready # Raw bytes were already completed exactly through BlockInput.

proc requestFinished*(download: var BlockDownload, id: BlockDownloadId): BlockDownloadError =
  ## Call only after the complete request and its native FIN have been queued; readiness never infers this event from response bytes.
  if download.stage != BlockDownloadStage.Receiving or download.pending.id != id:
    return BlockDownloadError.StaleDownload # Replayed write callbacks cannot complete a replacement.
  download.pending.requestFin = true
  download.finish()
  BlockDownloadError.None

proc append*(download: var BlockDownload, id: BlockDownloadId, fragment: openArray[byte],
    fin: bool): BlockDownloadError =
  ## Incrementally consume one E4-framed sequence, without decoding/hash/PVM work inside the transport callback.
  if download.stage notin [BlockDownloadStage.Receiving, BlockDownloadStage.Ready] or
      download.pending.id != id:
    return BlockDownloadError.StaleDownload # Late reset/data callbacks leave newer input unchanged.
  if download.stage == BlockDownloadStage.Ready or download.pending.responseFin:
    return BlockDownloadError.Busy # Completed bytes remain immutable until explicit producer work/acknowledgement.
  var cursor = 0
  while cursor < fragment.len and download.pending.headerBytes < 4:
    download.pending.header[download.pending.headerBytes] = fragment[cursor]
    inc download.pending.headerBytes
    inc cursor # Both positions are proven within the fixed header and current fragment.
  if download.pending.headerBytes == 4 and not download.pending.headerDone:
    var claimed = 0'u64
    for index in 0..<4: claimed = claimed or (uint64(download.pending.header[index]) shl (8 *
        index)) # E4, never a compact element count.
    if claimed > uint64(high(int)) or claimed > uint64(download.pending.resources.blockBytes) or
        claimed > uint64(download.pending.policies.reporting.admission.frame.maxBytes):
      return download.fail(BlockDownloadFailure(status: BlockDownloadError.LimitExceeded)) # No allocation before the whole claim is bounded.
    download.pending.headerDone = true
    download.pending.claimed = int(claimed)
    if claimed > 0:
      let admitted = download.input.begin(download.pending.original, ByteLimit(claimed),
        download.pending.ancestors, download.pending.resources, download.pending.policies)
      if admitted.error != BlockInputError.None:
        return download.fail(BlockDownloadFailure(status: BlockDownloadError.InputFailure,
            inputReason: admitted.error))
      download.pending.inputId = admitted.value
  if download.pending.headerDone and cursor < fragment.len:
    let count = fragment.len - cursor
    if count > download.pending.claimed - download.pending.received:
      return download.fail(BlockDownloadFailure(status: BlockDownloadError.Trailing)) # Extra bytes/second messages never enter raw input.
    let copied = download.input.append(download.pending.inputId, fragment.toOpenArray(cursor,
        fragment.high), false)
    if copied != BlockInputError.None:
      return download.fail(BlockDownloadFailure(status: BlockDownloadError.InputFailure,
          inputReason: copied))
    download.pending.received += count # Remaining capacity was proved before addition.
  if fin:
    if not download.pending.headerDone or download.pending.received != download.pending.claimed:
      return download.fail(BlockDownloadFailure(status: BlockDownloadError.Truncated)) # Header/body prefix is not a successful stream.
    if download.pending.claimed > 0:
      let completed = download.input.append(download.pending.inputId, [], true)
      if completed != BlockInputError.None:
        return download.fail(BlockDownloadFailure(status: BlockDownloadError.InputFailure,
            inputReason: completed))
    download.pending.responseFin = true
    download.finish()
  BlockDownloadError.None

proc cancel*(download: var BlockDownload, id: BlockDownloadId): bool =
  ## Cancel/acknowledge only this generation; callers still abort/retire their native stream before reusing callback storage.
  if download.stage == BlockDownloadStage.Idle or download.pending.id !=
      id: return false # Stale cancellation is inert.
  if download.input.stage != BlockInputStage.Idle:
    discard download.input.cancel(download.pending.inputId) # Active/Ready alternatives retain the matching raw-input identity.
  download.pending = default(PendingDownload)
  true

proc enqueue*(download: var BlockDownload, id: BlockDownloadId, owner: var Services,
    composition: AccumulationCompositionLimits): BlockDownloadResult[PreparedFinalAccumulation] =
  ## Explicit producer work consumes only complete streams; service ticks still perform canonical adoption separately.
  if download.pending.id != id or download.stage == BlockDownloadStage.Idle:
    return refused[PreparedFinalAccumulation](BlockDownloadError.StaleDownload) # No work against another stream generation.
  if download.stage != BlockDownloadStage.Ready:
    return refused[PreparedFinalAccumulation](BlockDownloadError.NotReady) # Empty/incomplete/failed streams authorize no execution.
  if owner.accumulationStage != AccumulationHandoffStage.Idle:
    return refused[PreparedFinalAccumulation](BlockDownloadError.Busy) # Keep Ready without decoding/hashing while adoption awaits acknowledgement.
  let prepared = owner.enqueueBlockInput(download.input, download.pending.inputId, composition)
  if prepared.error != BlockInputError.None:
    let reason = BlockDownloadFailure(status: BlockDownloadError.PreparationFailure,
        preparationReason: prepared)
    discard download.fail(reason)
    return BlockDownloadResult[PreparedFinalAccumulation](successful: false, refused: reason)
  download.pending = default(PendingDownload) # Success retains only the finalized certificate/handoff, never duplicate raw storage.
  BlockDownloadResult[PreparedFinalAccumulation](successful: true, completed: prepared.value)
