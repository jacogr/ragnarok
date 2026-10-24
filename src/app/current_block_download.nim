# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## CE 128 one-child request and bounded incremental response adapter over the independent current raw-block input owner.
## Native callbacks copy bytes/observe FIN; producers explicitly enqueue or lend Ready input to a joined worker later.

import std/assertions
import ./[chain, candidate, current_block_input, services, current_handoff, preparation_worker,
    current_logical_download]
import ../chain/[genesis, provider]
import ../codec/[bounded, header]
import ../state/[report_anchors, store, accumulation_current_update]

type
  CurrentBlockDownloadId* = distinct uint64 ## Local receiver generations are unrelated to QUIC handles and block identities.
  CurrentBlockDownloadStage* {.pure.} = enum ## Terminal empty/failure outcomes remain observable until explicit acknowledgement.
    Idle, Receiving, Ready, Preparing, Empty, Failed, AwaitingAncestors
  CurrentBlockDownloadError* {.pure.} = enum ## Successful framing is distinct from a usable finalized successor.
    Uninitialized, None, Busy, MissingHead, ProfileMismatch, LimitExceeded, InvalidAncestor,
    Exhausted, StaleDownload, NotReady, Truncated, Trailing, EmptyResponse, InputFailure,
    PreparationFailure, WorkerStartupFailure, WorkerFailure, Cancelled, HandoffFailure,
      NeedsAncestors,
    LogicalFailure
  CurrentBlockDownloadFailure* = object ## Only the actual selected failed child is retained; no successful prefix survives refusal.
    case status: CurrentBlockDownloadError
    of InputFailure:
      inputReason: CurrentBlockInputError
    of PreparationFailure:
      preparationReason: CurrentBlockInputResult
    of WorkerFailure:
      workerReason: PreparationError
    of HandoffFailure:
      handoffReason: CurrentHandoffAdmission
    of LogicalFailure:
      logicalReason: CurrentLogicalDownloadResult
    else:
      discard # Plain framing/readiness reasons retain no child owners.
  CurrentBlockDownloadResult*[T] = object ## Defaults are failures; only checked success authorizes generation/request/certificate access.
    case successful: bool
    of true:
      completed: T
    else:
      refused: CurrentBlockDownloadFailure
  PendingCurrentDownload = object ## Native stream ownership remains with the caller; this context retains only immutable application handles.
    id: CurrentBlockDownloadId
    case status: CurrentBlockDownloadStage
    of Receiving, Ready, Preparing, AwaitingAncestors:
      original: ApplicationChain
      ancestors: seq[OwnedHeader]
      resources: CurrentBlockInputLimits
      policies: CurrentCandidateLimits
      qualifyLogical: bool
      logicalPolicy: CurrentLogicalDownloadPolicy
      request: array[42, byte]
      header: array[4, byte]
      headerBytes, claimed, received: int
      headerDone, requestFin, responseFin: bool
      inputId: CurrentBlockInputId
      demand: ReportLookupDemand
    of Failed:
      refusal: CurrentBlockDownloadFailure
    else:
      discard # Idle/Empty retain neither payload nor canonical context.
  CurrentBlockDownload* = object ## One producer/callback owner; the nested input's mutable bytes must never be copied.
    next: uint64
    pending: PendingCurrentDownload
    input: CurrentBlockInput
    ticket: PreparationTicket
    logicalResult: CurrentLogicalDownloadResult

proc `=copy`*(destination: var CurrentBlockDownload,
    source: CurrentBlockDownload) {.error: "CurrentBlockDownload owns reception".}
  ## Composite ownership is explicit even though CurrentBlockInput already refuses copying.
proc `=dup`*(source: CurrentBlockDownload): CurrentBlockDownload {.error.}
  ## The nested receiver and worker borrow have exactly one stable owner.
proc requirePreparationRetired(download: CurrentBlockDownload) {.requires:
    download.pending.status != CurrentBlockDownloadStage.Preparing.} =
  ## Destruction cannot release input/history still borrowed by the Services worker.
  discard
proc `=destroy`*(download: CurrentBlockDownload) =
  ## Explicit collection/join must precede retirement of every captured ARC alias.
  requirePreparationRetired(download)
  `=destroy`(download.pending)
  `=destroy`(download.input)
  `=destroy`(download.ticket)
  `=destroy`(download.logicalResult)
proc `==`*(left, right: CurrentBlockDownloadId): bool {.borrow.}
  ## Compare only generations from this receiver's lifetime.

func stage*(download: CurrentBlockDownload): CurrentBlockDownloadStage =
  ## Observe readiness independently of the caller's still-live native stream handle.
  download.pending.status

func error*(reason: CurrentBlockDownloadFailure): CurrentBlockDownloadError =
  ## Inspect only the selected reason without allowing external retagging.
  reason.status

func error*[T](outcome: CurrentBlockDownloadResult[T]): CurrentBlockDownloadError =
  ## Defaults/refusals cannot masquerade as admitted generations or finalized success.
  if outcome.successful: CurrentBlockDownloadError.None
  else: outcome.refused.error # Failure has no usable generic payload.

func value*[T](outcome: CurrentBlockDownloadResult[T]): T {.inline, requires: outcome.successful.} =
  ## Extract only after selecting successful admission/request/preparation.
  outcome.completed

func failure*[T](outcome: CurrentBlockDownloadResult[T]): CurrentBlockDownloadFailure {.inline,
    requires: not outcome.successful.} =
  ## Inspect only an actual refused result, never an invented reason for success.
  outcome.refused

func failure*(download: CurrentBlockDownload): CurrentBlockDownloadFailure {.inline,
    requires: download.stage == CurrentBlockDownloadStage.Failed.} =
  ## Native consumers may acknowledge a retained framing/preparation failure after retiring the stream.
  download.pending.refusal

func inputError*(reason: CurrentBlockDownloadFailure): CurrentBlockInputError {.inline,
    requires: reason.status == CurrentBlockDownloadError.InputFailure.} =
  ## Inspect only the selected raw-input admission/reception error.
  reason.inputReason

func preparationFailure*(reason: CurrentBlockDownloadFailure): CurrentBlockInputResult {.inline,
    requires: reason.status == CurrentBlockDownloadError.PreparationFailure.} =
  ## Preserve only the actual failed preparation child, including codec/stage-specific diagnostics.
  reason.preparationReason

func workerError*(reason: CurrentBlockDownloadFailure): PreparationError {.inline,
    requires: reason.status == CurrentBlockDownloadError.WorkerFailure.} =
  ## Inspect only an actual worker admission refusal.
  reason.workerReason
func handoffError*(reason: CurrentBlockDownloadFailure): CurrentHandoffAdmission {.inline,
    requires: reason.status == CurrentBlockDownloadError.HandoffFailure.} =
  ## Preserve only an actual host enqueue refusal after execution has retired.
  reason.handoffReason

func logicalFailure*(reason: CurrentBlockDownloadFailure): CurrentLogicalDownloadResult {.inline,
    requires: reason.status == CurrentBlockDownloadError.LogicalFailure.} =
  ## Only an actual failed post-collection qualification exposes its exact State stage.
  reason.logicalReason
func logicalCompletion*(download: CurrentBlockDownload): CurrentLogicalDownloadResult {.inline,
    requires: download.stage == CurrentBlockDownloadStage.Idle.} =
  ## Observe the qualified result only after successful enqueue; default/nonlogical generations expose Uninitialized.
  download.logicalResult

func refused[T](reason: CurrentBlockDownloadError): CurrentBlockDownloadResult[T] =
  ## Construct a plain refusal without a successful payload or unrelated child error.
  CurrentBlockDownloadResult[T](successful: false, refused: CurrentBlockDownloadFailure(
      status: reason))

proc fail(download: var CurrentBlockDownload, reason: CurrentBlockDownloadFailure): CurrentBlockDownloadError =
  ## Retire every partial raw/context owner while retaining only the selected failure and callback identity.
  let id = download.pending.id
  if download.input.stage != CurrentBlockInputStage.Idle:
    discard download.input.cancel(download.pending.inputId) # Only this receiver can own the nested generation.
  download.pending = PendingCurrentDownload(status: CurrentBlockDownloadStage.Failed, id: id,
      refusal: reason)
  reason.error

proc begin*(download: var CurrentBlockDownload, chain: ApplicationChain,
    ancestors: openArray[OwnedHeader], resources: CurrentBlockInputLimits,
    policies: CurrentCandidateLimits): CurrentBlockDownloadResult[CurrentBlockDownloadId] =
  ## Bound retained context before any request is emitted; the exact response extent arrives later in its E4 header.
  if download.stage != CurrentBlockDownloadStage.Idle:
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.Busy) # Terminal outcomes also require acknowledgement.
  let selected = chain.chainView.bestBlock
  if selected.error != GenesisError.None or chain.stateSnapshot.error != StateStoreError.None:
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.MissingHead) # No implicit requested hash or complete map.
  let head = selected.value
  let frame = policies.reporting.admission.frame
  # GP valcount permits independent roster sizes; the decoder ceiling covers the head up to three validators per core.
  if uint64(frame.cores) != uint64(head.cores) or
      uint64(frame.validators) < uint64(head.activeValidators) or
      uint64(frame.validators) mod 3 != 0 or
      uint64(frame.validators) div 3 > uint64(head.cores) or
      uint64(frame.epochSlots) != uint64(head.epochSlots):
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.ProfileMismatch) # Refuse unrelated profile without hashing.
  if uint64(resources.blockBytes) == 0 or uint64(frame.maxBytes) == 0 or
      uint64(ancestors.len) > uint64(resources.ancestors):
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.LimitExceeded) # Context retention has its own preflight before response framing.
  var remaining = uint64(resources.ancestorBytes)
  for ancestor in ancestors:
    let info = ancestor.headerInfo
    if info.error != HeaderError.None:
      return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.InvalidAncestor) # Never retain a default header as context.
    if uint64(info.value.consumed) > remaining:
      return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.LimitExceeded) # Prove cumulative bytes by subtraction.
    remaining -= uint64(info.value.consumed)
  if download.next == high(uint64):
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.Exhausted) # A late callback never sees a wrapped generation.
  var retained = newSeq[OwnedHeader](ancestors.len)
  for index, ancestor in ancestors: retained[index] = ancestor # Retain handles independently of caller sequence backing.
  var request = default(array[42, byte])
  request[0] = 128
  request[1] = 37
  for index, octet in array[32, byte](head.blockHash): request[5 +
      index] = octet # The captured head alone supplies the start hash.
  request[38] = 1 # Direction zero and E4 maximum one; all other fixed bytes were initialized to zero.
  download.logicalResult = default(CurrentLogicalDownloadResult) # A new admitted generation retires any previous host-only completion.
  inc download.next
  let id = CurrentBlockDownloadId(download.next)
  download.pending = PendingCurrentDownload(status: CurrentBlockDownloadStage.Receiving, id: id,
    original: chain, ancestors: retained, resources: resources, policies: policies,
    request: request, header: default(array[4, byte]), headerBytes: 0, claimed: 0, received: 0,
    headerDone: false, requestFin: false, responseFin: false, inputId: default(CurrentBlockInputId))
  CurrentBlockDownloadResult[CurrentBlockDownloadId](successful: true, completed: id)

proc begin*(download: var CurrentBlockDownload, owner: Services, ancestors: openArray[OwnedHeader],
    resources: CurrentBlockInputLimits, policies: CurrentCandidateLimits): CurrentBlockDownloadResult[
        CurrentBlockDownloadId] =
  ## Select the service's immutable canonical history without exposing its mutable ApplicationChain owner.
  let chain = initApplicationChain(owner.chainView)
  if chain.error != ApplicationChainError.None:
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.MissingHead) # Closed/default services have no requested head.
  download.begin(chain.value, ancestors, resources, policies)

proc begin*(download: var CurrentBlockDownload, owner: Services, ancestors: openArray[OwnedHeader],
    resources: CurrentBlockInputLimits, policies: CurrentCandidateLimits,
    logical: CurrentLogicalDownloadPolicy): CurrentBlockDownloadResult[CurrentBlockDownloadId] =
  ## Opt in before worker submission; the immutable source/policy stays untouched until matching collection or joined retirement.
  if not owner.preparationAvailable:
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.Busy) # Inspect no shared canonical/logical owner while another managed lease is active.
  let admitted = download.begin(owner, ancestors, resources, policies)
  if admitted.error == CurrentBlockDownloadError.None:
    download.pending.qualifyLogical = true
    download.pending.logicalPolicy = logical # Retain only after complete generation admission on the open host gate.
  admitted

proc request*(download: CurrentBlockDownload, id: CurrentBlockDownloadId): CurrentBlockDownloadResult[
    array[42, byte]] =
  ## Copy the complete fixed request; callers own partial-write offsets and queue FIN only after all 42 bytes.
  if download.stage notin [CurrentBlockDownloadStage.Receiving, CurrentBlockDownloadStage.Ready] or
      download.pending.id != id:
    return refused[array[42, byte]](CurrentBlockDownloadError.StaleDownload) # No request for a different/retired callback generation.
  CurrentBlockDownloadResult[array[42, byte]](successful: true, completed: download.pending.request)

proc finish(download: var CurrentBlockDownload) =
  ## Complete framing only when both stream directions ended cleanly; a valid empty sequence contains no candidate.
  if download.pending.requestFin and download.pending.responseFin:
    if download.pending.claimed == 0:
      download.pending = PendingCurrentDownload(status: CurrentBlockDownloadStage.Empty,
          id: download.pending.id) # Release captured history too.
    else:
      download.pending.status = CurrentBlockDownloadStage.Ready # Raw bytes were already completed exactly through CurrentBlockInput.

proc requestFinished*(download: var CurrentBlockDownload,
    id: CurrentBlockDownloadId): CurrentBlockDownloadError =
  ## Call only after the complete request and its native FIN have been queued; readiness never infers this event from response bytes.
  if download.stage != CurrentBlockDownloadStage.Receiving or download.pending.id != id:
    return CurrentBlockDownloadError.StaleDownload # Replayed write callbacks cannot complete a replacement.
  download.pending.requestFin = true
  download.finish()
  CurrentBlockDownloadError.None

proc append*(download: var CurrentBlockDownload, id: CurrentBlockDownloadId, fragment: openArray[
    byte], fin: bool): CurrentBlockDownloadError =
  ## Incrementally consume one E4-framed sequence, without decoding/hash/PVM work inside the transport callback.
  if download.stage notin [CurrentBlockDownloadStage.Receiving, CurrentBlockDownloadStage.Ready] or
      download.pending.id != id:
    return CurrentBlockDownloadError.StaleDownload # Late reset/data callbacks leave newer input unchanged.
  if download.stage == CurrentBlockDownloadStage.Ready or download.pending.responseFin:
    return CurrentBlockDownloadError.Busy # Completed bytes remain immutable until explicit producer work/acknowledgement.
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
      return download.fail(CurrentBlockDownloadFailure(
          status: CurrentBlockDownloadError.LimitExceeded)) # No allocation before the whole claim is bounded.
    download.pending.headerDone = true
    download.pending.claimed = int(claimed)
    if claimed > 0:
      let admitted = download.input.begin(download.pending.original, ByteLimit(claimed),
        download.pending.ancestors, download.pending.resources, download.pending.policies)
      if admitted.error != CurrentBlockInputError.None:
        return download.fail(CurrentBlockDownloadFailure(
            status: CurrentBlockDownloadError.InputFailure, inputReason: admitted.error))
      download.pending.inputId = admitted.value
  if download.pending.headerDone and cursor < fragment.len:
    let count = fragment.len - cursor
    if count > download.pending.claimed - download.pending.received:
      return download.fail(CurrentBlockDownloadFailure(
          status: CurrentBlockDownloadError.Trailing)) # Extra bytes/second messages never enter raw input.
    let copied = download.input.append(download.pending.inputId, fragment.toOpenArray(cursor,
        fragment.high), false)
    if copied != CurrentBlockInputError.None:
      return download.fail(CurrentBlockDownloadFailure(
          status: CurrentBlockDownloadError.InputFailure, inputReason: copied))
    download.pending.received += count # Remaining capacity was proved before addition.
  if fin:
    if not download.pending.headerDone or download.pending.received != download.pending.claimed:
      return download.fail(CurrentBlockDownloadFailure(
          status: CurrentBlockDownloadError.Truncated)) # Header/body prefix is not a successful stream.
    if download.pending.claimed > 0:
      let completed = download.input.append(download.pending.inputId, [], true)
      if completed != CurrentBlockInputError.None:
        return download.fail(CurrentBlockDownloadFailure(
            status: CurrentBlockDownloadError.InputFailure, inputReason: completed))
    download.pending.responseFin = true
    download.finish()
  CurrentBlockDownloadError.None

proc cancel*(download: var CurrentBlockDownload, id: CurrentBlockDownloadId): bool =
  ## Cancel/acknowledge only this generation; callers still abort/retire their native stream before reusing callback storage.
  if download.stage == CurrentBlockDownloadStage.Idle or download.pending.id !=
      id: return false # Stale cancellation is inert.
  if download.stage == CurrentBlockDownloadStage.Preparing: return false # Cancellation must retain the worker lease until collection/join.
  if download.input.stage != CurrentBlockInputStage.Idle:
    discard download.input.cancel(download.pending.inputId) # Active/Ready alternatives retain the matching raw-input identity.
  download.pending = default(PendingCurrentDownload)
  true

proc beginPreparation*(download: var CurrentBlockDownload, id: CurrentBlockDownloadId,
    owner: var Services): CurrentBlockDownloadResult[PreparationTicket] =
  ## Borrow exact Ready bytes only after the caller has retired native callbacks; never expose mutable input storage.
  if download.pending.id != id or download.stage == CurrentBlockDownloadStage.Idle:
    return refused[PreparationTicket](CurrentBlockDownloadError.StaleDownload)
  if download.stage != CurrentBlockDownloadStage.Ready:
    return refused[PreparationTicket](CurrentBlockDownloadError.NotReady)
  if not owner.preparationAvailable:
    return refused[PreparationTicket](CurrentBlockDownloadError.Busy) # Scalar gate prevents canonical graph access during another lease.
  var admitted = default(PreparationAdmission)
  try:
    admitted = owner.beginPreparation(download.input, download.pending.inputId)
  except:
    let reason = CurrentBlockDownloadFailure(status: CurrentBlockDownloadError.WorkerStartupFailure)
    discard download.fail(reason)
    return CurrentBlockDownloadResult[PreparationTicket](successful: false,
        refused: reason) # No worker borrow survives failed thread creation.
  if admitted.error != PreparationError.None:
    let reason = CurrentBlockDownloadFailure(status: CurrentBlockDownloadError.WorkerFailure,
        workerReason: admitted.error)
    discard download.fail(reason)
    return CurrentBlockDownloadResult[PreparationTicket](successful: false, refused: reason)
  download.ticket = admitted.value # Host-only identity never aliases the worker's ARC graph.
  download.pending.status = CurrentBlockDownloadStage.Preparing # The active variants share all fields; no captured owner is retired.
  CurrentBlockDownloadResult[PreparationTicket](successful: true, completed: admitted.value)

proc cancelPreparation*(download: var CurrentBlockDownload, id: CurrentBlockDownloadId,
    owner: var Services): bool =
  ## Mark unwanted work without touching the input, retained parent or ancestor handles.
  if download.pending.id != id or download.stage !=
      CurrentBlockDownloadStage.Preparing: return false
  owner.cancelPreparation(download.ticket)

proc collectPreparation*(download: var CurrentBlockDownload, id: CurrentBlockDownloadId,
    owner: var Services): CurrentBlockDownloadResult[
        PreparedCurrentChainUpdate] =
  ## End the managed lease before inspecting pipeline results or changing any raw/canonical owner.
  if download.pending.id != id or download.stage != CurrentBlockDownloadStage.Preparing:
    return refused[PreparedCurrentChainUpdate](CurrentBlockDownloadError.StaleDownload)
  let completion = owner.collectPreparation(download.ticket)
  if completion.kind == PreparationCompletionKind.Uninitialized:
    return refused[PreparedCurrentChainUpdate](CurrentBlockDownloadError.NotReady) # Running/stale collection retains capacity and all graph aliases.
  download.ticket = default(PreparationTicket)
  if completion.kind == PreparationCompletionKind.Cancelled:
    let reason = CurrentBlockDownloadFailure(status: CurrentBlockDownloadError.Cancelled)
    discard download.fail(reason)
    return CurrentBlockDownloadResult[PreparedCurrentChainUpdate](successful: false,
        refused: reason)
  assert completion.kind == PreparationCompletionKind.CurrentCompleted
  let prepared = completion.currentValue
  if prepared.error == CurrentBlockInputError.NeedsAncestors:
    download.pending.demand = prepared.ancestorDemand
    download.pending.status = CurrentBlockDownloadStage.AwaitingAncestors
    return refused[PreparedCurrentChainUpdate](CurrentBlockDownloadError.NeedsAncestors) # Collection ended the lease; neither input nor original block is discarded.
  if prepared.error != CurrentBlockInputError.None:
    let reason = CurrentBlockDownloadFailure(status: CurrentBlockDownloadError.PreparationFailure,
        preparationReason: prepared)
    discard download.fail(reason)
    return CurrentBlockDownloadResult[PreparedCurrentChainUpdate](successful: false,
        refused: reason)
  var logical = default(CurrentLogicalDownloadResult)
  if download.pending.qualifyLogical:
    logical = qualifyCurrentDownload(download.pending.logicalPolicy, prepared.value)
    if logical.error != CurrentLogicalDownloadError.None:
      let reason = CurrentBlockDownloadFailure(status: CurrentBlockDownloadError.LogicalFailure,
          logicalReason: logical)
      discard download.fail(reason) # Matching collection already ended the lease; no failed logical prefix reaches the handoff.
      return CurrentBlockDownloadResult[PreparedCurrentChainUpdate](successful: false,
          refused: reason)
  let queued = owner.enqueueCurrentAccumulation(prepared.value)
  if queued != CurrentHandoffAdmission.None:
    let reason = CurrentBlockDownloadFailure(status: CurrentBlockDownloadError.HandoffFailure,
        handoffReason: queued)
    discard download.fail(reason)
    return CurrentBlockDownloadResult[PreparedCurrentChainUpdate](successful: false,
        refused: reason)
  download.logicalResult = logical # Publish logical completion only after the exact genuine update was successfully enqueued.
  download.pending = default(PendingCurrentDownload) # All worker aliases retired before host adoption owns the certificate.
  CurrentBlockDownloadResult[PreparedCurrentChainUpdate](successful: true,
      completed: prepared.value)

proc retirePreparation*(download: var CurrentBlockDownload, id: CurrentBlockDownloadId,
    owner: var Services): bool =
  ## Explicit shutdown joins before dropping a queued/running/Done input lease and never enqueues a certificate.
  if download.pending.id != id or download.stage !=
      CurrentBlockDownloadStage.Preparing: return false
  owner.stopPreparation()
  download.ticket = default(PreparationTicket)
  discard download.input.cancel(download.pending.inputId) # Joined shutdown permits either consumed or queued-cancelled raw input.
  download.pending = default(PendingCurrentDownload)
  true

proc ancestorDemand*(download: CurrentBlockDownload,
    id: CurrentBlockDownloadId): CurrentBlockDownloadResult[ReportLookupDemand] =
  ## Observe the original certified plan only after native retirement and managed worker collection.
  if download.pending.id != id or download.stage == CurrentBlockDownloadStage.Idle:
    return refused[ReportLookupDemand](CurrentBlockDownloadError.StaleDownload)
  if download.stage != CurrentBlockDownloadStage.AwaitingAncestors:
    return refused[ReportLookupDemand](CurrentBlockDownloadError.NotReady)
  CurrentBlockDownloadResult[ReportLookupDemand](successful: true,
      completed: download.pending.demand)

proc resumeAncestors*(download: var CurrentBlockDownload, id: CurrentBlockDownloadId,
    owner: Services, ancestors: openArray[OwnedHeader]): CurrentBlockDownloadResult[
        CurrentBlockDownloadId] =
  ## End-to-end resumption preserves callback/input generations and does no guest execution or network work.
  if download.pending.id != id or download.stage == CurrentBlockDownloadStage.Idle:
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.StaleDownload)
  if download.stage != CurrentBlockDownloadStage.AwaitingAncestors:
    return refused[CurrentBlockDownloadId](CurrentBlockDownloadError.NotReady)
  if not owner.preparationAvailable: return refused[CurrentBlockDownloadId](
      CurrentBlockDownloadError.Busy)
  let chain = initApplicationChain(owner.chainView)
  if chain.error != ApplicationChainError.None: return refused[CurrentBlockDownloadId](
      CurrentBlockDownloadError.MissingHead)
  let resumed = download.input.resumeAncestors(download.pending.inputId, chain.value, ancestors)
  if resumed != CurrentBlockInputError.None:
    return CurrentBlockDownloadResult[CurrentBlockDownloadId](successful: false,
      refused: CurrentBlockDownloadFailure(status: CurrentBlockDownloadError.InputFailure,
          inputReason: resumed))
  download.pending.demand = default(ReportLookupDemand)
  download.pending.status = CurrentBlockDownloadStage.Ready # Only a later explicit submission can borrow the prepared input again.
  CurrentBlockDownloadResult[CurrentBlockDownloadId](successful: true, completed: id)
