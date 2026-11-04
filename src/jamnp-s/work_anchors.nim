# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-bound package anchor validation precedes guarantee eligibility; no signature or admission authority is produced here.
import ./work_submission
import ../chain/[provider, genesis, parameters]
import ../codec/[bounded, header]
import ../codec/state/[history, layout, safrole]
import ../state/[store, ancestor_context]
import ../state/history as history_transition
import ../state/report/anchors

type
  WorkAnchorLimits* = object ## Explicit history/header decode and aggregate-byte budgets are independent of protocol age limits.
    history*: HistoryConfig
    ancestors*: AncestorContextLimits
  WorkAnchorError* {.pure.} = enum ## Default/refused checks carry no source capability or accepted prefix.
    Uninitialized, None, InvalidSource, InvalidPolicy, InvalidSlot, LimitExceeded,
    HistoryFailure, CorrectionFailure, RecentFailure, AncestryFailure, LookupFailure
  WorkAnchorInfo* = object ## Detached source identity and potential inclusion slot convey no credential authority.
    head*: genesis.BlockHash
    inclusionSlot*: StateTime
  WorkAnchorData = ref object ## Only the exact original header and complete posterior map may reuse this immutable qualification.
    header: WorkSubmissionHeader
    source: StateStoreSnapshot
    history: HistorySnapshot
    info: WorkAnchorInfo
  AnchoredWorkContext* = object ## Context validity is separate from authorization, package eligibility and actual report computation.
    data: nil WorkAnchorData
  WorkAnchorResult*[T] = object ## Preserve genuine child reasons; failures cannot expose a qualified header or state.
    case status: WorkAnchorError
    of None: completed: T
    of HistoryFailure: historyReason: HistoryError
    of CorrectionFailure: correctionReason: HistoryTransitionError
    of RecentFailure: recentReason: ReportAnchorError
    of AncestryFailure, LookupFailure: ancestorReason: AncestorContextError
    else: discard # Local policy/source refusals retain only their reason.
func error*[T](outcome: WorkAnchorResult[T]): WorkAnchorError =
  ## Inspect failure without allowing a caller to retag an owner.
  outcome.status
func value*[T](outcome: WorkAnchorResult[T]): T {.requires: outcome.status ==
    WorkAnchorError.None.} =
  ## Only complete source/context qualification exposes a capability.
  outcome.completed
func historyError*[T](outcome: WorkAnchorResult[T]): HistoryError {.requires: outcome.status ==
    WorkAnchorError.HistoryFailure.} =
  ## Retain the actual exact-history decoder refusal.
  outcome.historyReason
func correctionFailed[T](outcome: WorkAnchorResult[T]): bool =
  ## Keep the selected correction alternative explicit for contracts and the pinned formatter.
  outcome.status == WorkAnchorError.CorrectionFailure
func correctionError*[T](outcome: WorkAnchorResult[
    T]): HistoryTransitionError {.requires: correctionFailed(outcome).} =
  ## Retain the actual bounded history-correction refusal.
  outcome.correctionReason
func recentError*[T](outcome: WorkAnchorResult[T]): ReportAnchorError {.requires: outcome.status ==
    WorkAnchorError.RecentFailure.} =
  ## Retain the shared GP tuple/age refusal.
  outcome.recentReason
func ancestorError*[T](outcome: WorkAnchorResult[T]): AncestorContextError {.requires: outcome.status in
    {WorkAnchorError.AncestryFailure, WorkAnchorError.LookupFailure}.} =
  ## Retain actual retained-header ancestry or lookup-root refusal.
  outcome.ancestorReason
func failure[T](reason: WorkAnchorError): WorkAnchorResult[T] {.requires: reason in {
    WorkAnchorError.InvalidSource, WorkAnchorError.InvalidPolicy, WorkAnchorError.InvalidSlot,
    WorkAnchorError.LimitExceeded}.} =
  ## Local refusals cannot fabricate a successful context or child failure.
  WorkAnchorResult[T](status: reason)
proc anchorInfo*(context: AnchoredWorkContext): WorkAnchorResult[WorkAnchorInfo] =
  ## Copy fixed facts only while the caller owns graph access; a default context exposes no fabricated head or slot.
  let data = context.data
  if data == nil: return WorkAnchorResult[WorkAnchorInfo](status: WorkAnchorError.Uninitialized)
  WorkAnchorResult[WorkAnchorInfo](status: WorkAnchorError.None, completed: data.info)
proc workAnchorHistory*(context: AnchoredWorkContext): WorkAnchorResult[HistorySnapshot] =
  ## Share only the exact bounded corrected C3 used to qualify this original header and source map.
  let data = context.data
  if data == nil: return WorkAnchorResult[HistorySnapshot](status: WorkAnchorError.Uninitialized)
  WorkAnchorResult[HistorySnapshot](status: WorkAnchorError.None, completed: data.history)
proc anchoredWorkMatches*(context: AnchoredWorkContext, header: WorkSubmissionHeader,
    state: StateStoreSnapshot): bool =
  ## Byte-identical independently decoded headers or substituted posterior maps cannot borrow this capability.
  let data = context.data
  if data == nil: return false
  data.header.sameSubmissionHeader(header) and sameStateSnapshot(data.source, state)
proc captureWorkAnchors*(original: WorkSubmissionHeader, view: ChainView, now: StateTime,
    limits: WorkAnchorLimits): WorkAnchorResult[AnchoredWorkContext] =
  ## Check possible next-block context against actual complete state and linked retained headers, under one private graph lease.
  let head = view.bestBlock
  let selected = original.submissionContext
  if head.error != GenesisError.None or selected.error != WorkSubmissionError.None:
    return failure[AnchoredWorkContext](WorkAnchorError.InvalidSource)
  if view.fuzzOnly: return failure[AnchoredWorkContext](WorkAnchorError.InvalidSource)
  let source = head.value
  let parameters = source.chainParameters
  if not parameters.valid or uint64(limits.history.cores) != parameters.get(coreCount):
    return failure[AnchoredWorkContext](WorkAnchorError.InvalidPolicy)
  if source.slot == high(uint32) or uint32(now) < source.slot:
    return failure[AnchoredWorkContext](WorkAnchorError.InvalidSlot)
  let inclusion = max(source.slot+1, uint32(now)) # A potential next block is strictly after its actual parent, even in a skipped-slot gap.
  let chapter = source.lookup(chapterKey(StateChapter(3)))
  if chapter.error != StateStoreError.None: return failure[AnchoredWorkContext](
      WorkAnchorError.InvalidSource)
  if uint64(chapter.value.byteLength) > uint64(limits.history.maxBytes):
    return failure[AnchoredWorkContext](WorkAnchorError.LimitExceeded)
  let decoded = decodeHistoryState(chapter.value.bytes, limits.history)
  if decoded.error != HistoryError.None:
    return WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.HistoryFailure,
        historyReason: decoded.error)
  if decoded.value.consumed != chapter.value.byteLength: return failure[AnchoredWorkContext](
      WorkAnchorError.InvalidSource)
  let corrected = correctHistoryParent(decoded.value.snapshot,
    HistoryStateRoot(array[32, byte](source.stateRoot)), limits.history)
  if corrected.error != HistoryTransitionError.None:
    return WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.CorrectionFailure,
        correctionReason: corrected.error)
  let history = decodeHistoryState(corrected.value.value, limits.history)
  if history.error != HistoryError.None:
    return WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.HistoryFailure,
        historyReason: history.error)
  let context = selected.value
  let recent = inspectRefinementAnchor(context, history.value.snapshot, StateTime(inclusion),
    LookupAge(parameters.get(maxLookupAnchorAge)))
  if recent != ReportAnchorError.None:
    return WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.RecentFailure,
        recentReason: recent)
  if context.lookupAnchor.bytes == array[32, byte](source.blockHash):
    # The trusted complete head map proves this root before the future child's prior-state commitment exists.
    if uint32(context.lookupSlot) != source.slot:
      return WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.LookupFailure,
          ancestorReason: AncestorContextError.WrongLookupSlot)
    if context.lookupStateRoot.bytes != array[32, byte](source.stateRoot):
      return WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.LookupFailure,
          ancestorReason: AncestorContextError.WrongLookupState)
  else:
    let count = view.validationHeaderCount
    if count < 1: return failure[AnchoredWorkContext](WorkAnchorError.InvalidSource)
    if uint64(count) > uint64(limits.ancestors.headers): return failure[AnchoredWorkContext](
        WorkAnchorError.LimitExceeded)
    if count > high(int) div sizeof(OwnedHeader): return failure[AnchoredWorkContext](
        WorkAnchorError.LimitExceeded)
    var bytes = 0'u64
    for index in 0..<count:
      # Preflight the whole selected chain before allocating a descriptor index or copying sealed bytes.
      let header = view.validationHeaderAt(ValidationHeaderIndex(index)).header
      let size = uint64(header.headerInfo.value.consumed)
      if bytes > uint64(limits.ancestors.maxBytes): return failure[AnchoredWorkContext](
          WorkAnchorError.LimitExceeded)
      if size > uint64(limits.ancestors.maxBytes)-bytes: return failure[AnchoredWorkContext](
          WorkAnchorError.LimitExceeded)
      bytes += size
    var older = newSeq[OwnedHeader](count-1)
    for index in 0..<older.len:
      # The view stores oldest first; the shared verifier requires newest first after the parent.
      older[index] = view.validationHeaderAt(ValidationHeaderIndex(count-2-index)).header
    let chain = captureAncestorContext(source.header, older, limits.ancestors)
    if chain.error != AncestorContextError.None:
      return WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.AncestryFailure,
          ancestorReason: chain.error)
    let located = chain.value.findLookupAnchor(HeaderParent(context.lookupAnchor.bytes),
      HeaderSlot(uint32(context.lookupSlot)), PriorStateRoot(context.lookupStateRoot.bytes))
    if located.error != AncestorContextError.None:
      return WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.LookupFailure,
          ancestorReason: located.error)
  WorkAnchorResult[AnchoredWorkContext](status: WorkAnchorError.None,
    completed: AnchoredWorkContext(data:
    WorkAnchorData(header: original, source: source.stateSnapshot, history: history.value.snapshot,
      info: WorkAnchorInfo(head: source.blockHash, inclusionSlot: StateTime(inclusion)))))
