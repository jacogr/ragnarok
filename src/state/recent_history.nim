# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind recent C(3) to one completed post-ready source, its sealed child header, finalized outputs and original verified guarantees.
## Preparation may hash without writes; atomic publication preserves the exact complete post-ready map and inherited limits.

import ../codec/[bounded, header, owned, report_owned, state_history, state_outputs, state_layout, state_trie]
import ../crypto/primitives
import ./[history, ready_reconciliation, accumulation_publication, block_activity, service_activity,
  accumulation_statistics, accumulation_finalization, accumulation_outputs, accumulation_execution,
  accumulation_round, accumulation_queue, report_admission, guarantee_credentials, block_transition,
  block_admission, store]

type
  RecentHistoryConfig* = object ## Source capture and output-root work have independent ceilings from complete history framing.
    history*: HistoryConfig
    outputs*: OutputLogConfig
    headerBytes*: ByteLimit
  RecentHistoryInfo* = object ## Copied exact source identities/cardinalities expose no mutable histories or output arrays.
    header*: HistoryHeaderHash
    parentState*: HistoryStateRoot
    slot*: HistorySlot
    accumulation*: history.AccumulationRoot
    outputs*, guarantees*: int
    history*: HistoryInfo
  RecentHistoryError* {.pure.} = enum ## Defaults/refusals retain only selected precise reasons.
    Uninitialized,                    ## Default owner/result.
    None,                             ## Complete selected success.
    InvalidSource,                    ## No genuine completed ready-publication source.
    InvalidConfig,                    ## Caller history core domain disagrees with the original block.
    InvalidState,                     ## Required original C(3)/header/store is missing or inexact.
    ForeignState,                     ## Mutable caller does not own the exact post-ready prior.
    LimitExceeded,                    ## Source header/output/package/capture/native work exceeds policy.
    CodecFailure,                     ## Inspect the history input/output codec refusal.
    CryptoFailure,                    ## Inspect sealed-header hashing refusal.
    OutputFailure,                    ## Inspect finalized-output tree refusal.
    HistoryFailure,                   ## Inspect belt/recent-history advancement refusal.
    StateFailure                      ## Inspect atomic store/backend refusal.
  RecentData = ref object # Acyclic source graph owns copied canonical bytes and immutable decoded history.
    source: PublishedReadyReconciliation
    prior: StateStoreSnapshot
    entry: StateEntry
    snapshot: HistorySnapshot
    info: RecentHistoryInfo
  PreparedRecentHistory* = object ## Only source-derived complete context authorizes this scoped recent-history step.
    data: nil RecentData
  PublishedData = ref object # Complete immutable successor retains exact preparation without mutable caller aliases.
    source: PreparedRecentHistory
    state: StateStoreSnapshot
  PublishedRecentHistory* = object ## Recent-history publication leaves remaining extrinsic/block validity gates open.
    data: nil PublishedData
  RecentHistoryResult*[T] = object ## Private alternatives guard all values and unrelated failure reasons.
    case status: RecentHistoryError
    of None:
      completed: T # Only complete selected success contains data.
    of CodecFailure:
      codecReason: HistoryError
    of CryptoFailure:
      cryptoReason: CryptoError
    of OutputFailure:
      outputReason: HistoryTransitionError
    of HistoryFailure:
      historyReason: HistoryTransitionError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # No partial history, root or usable map survives refusal.

func error*[T](outcome: RecentHistoryResult[T]): RecentHistoryError =
  ## Inspect the immutable selected reason.
  outcome.status
func value*[T](outcome: RecentHistoryResult[T]): T {.inline,
    requires: outcome.status == RecentHistoryError.None.} =
  ## Extract only complete selected success under checked optimized contracts.
  outcome.completed
func codecError*[T](outcome: RecentHistoryResult[T]): HistoryError {.inline,
    requires: outcome.status == RecentHistoryError.CodecFailure.} =
  ## Inspect only a genuine selected history codec refusal.
  outcome.codecReason
func cryptoError*[T](outcome: RecentHistoryResult[T]): CryptoError {.inline,
    requires: outcome.status == RecentHistoryError.CryptoFailure.} =
  ## Inspect only a sealed-header hash refusal.
  outcome.cryptoReason
func outputError*[T](outcome: RecentHistoryResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == RecentHistoryError.OutputFailure.} =
  ## Inspect only a finalized-output tree refusal.
  outcome.outputReason
func historyError*[T](outcome: RecentHistoryResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == RecentHistoryError.HistoryFailure.} =
  ## Inspect only a belt/recent-history transition refusal.
  outcome.historyReason
func stateError*[T](outcome: RecentHistoryResult[T]): StateStoreError {.inline,
    requires: outcome.status == RecentHistoryError.StateFailure.} =
  ## Inspect only a genuine atomic publication refusal.
  outcome.stateReason

proc recentHistoryInfo*(plan: PreparedRecentHistory): RecentHistoryResult[RecentHistoryInfo] =
  ## Copy exact derived identities, output/guarantee counts and resulting history cardinalities.
  let data = plan.data
  if data == nil: return RecentHistoryResult[RecentHistoryInfo](
      status: RecentHistoryError.Uninitialized)
  RecentHistoryResult[RecentHistoryInfo](status: RecentHistoryError.None, completed: data.info)
proc recentHistorySource*(plan: PreparedRecentHistory): RecentHistoryResult[
    PublishedReadyReconciliation] =
  ## Retain the complete post-ready source independently of caller handles.
  let data = plan.data
  if data == nil: return RecentHistoryResult[PublishedReadyReconciliation](
      status: RecentHistoryError.Uninitialized)
  RecentHistoryResult[PublishedReadyReconciliation](status: RecentHistoryError.None,
      completed: data.source)
proc recentHistoryPrior*(plan: PreparedRecentHistory): RecentHistoryResult[StateStoreSnapshot] =
  ## Retain the exact complete map required by mutable publication.
  let data = plan.data
  if data == nil: return RecentHistoryResult[StateStoreSnapshot](
      status: RecentHistoryError.Uninitialized)
  RecentHistoryResult[StateStoreSnapshot](status: RecentHistoryError.None, completed: data.prior)
proc recentHistoryEntry*(plan: PreparedRecentHistory): RecentHistoryResult[StateEntry] =
  ## Copy canonical C(3) bytes; caller mutations cannot alter publication input.
  let data = plan.data
  if data == nil: return RecentHistoryResult[StateEntry](status: RecentHistoryError.Uninitialized)
  RecentHistoryResult[StateEntry](status: RecentHistoryError.None, completed: data.entry)
proc recentHistorySnapshot*(plan: PreparedRecentHistory): RecentHistoryResult[HistorySnapshot] =
  ## Retain immutable history records/peaks for the existing nominal codec accessors.
  let data = plan.data
  if data == nil: return RecentHistoryResult[HistorySnapshot](
      status: RecentHistoryError.Uninitialized)
  RecentHistoryResult[HistorySnapshot](status: RecentHistoryError.None, completed: data.snapshot)
proc publishedRecentSource*(plan: PublishedRecentHistory): RecentHistoryResult[
    PreparedRecentHistory] =
  ## Retain the exact derived history preparation that authorized this successor.
  let data = plan.data
  if data == nil: return RecentHistoryResult[PreparedRecentHistory](
      status: RecentHistoryError.Uninitialized)
  RecentHistoryResult[PreparedRecentHistory](status: RecentHistoryError.None,
      completed: data.source)
proc publishedRecentState*(plan: PublishedRecentHistory): RecentHistoryResult[StateStoreSnapshot] =
  ## Retain the immutable complete successor without exposing a mutable store alias.
  let data = plan.data
  if data == nil: return RecentHistoryResult[StateStoreSnapshot](
      status: RecentHistoryError.Uninitialized)
  RecentHistoryResult[StateStoreSnapshot](status: RecentHistoryError.None, completed: data.state)

proc prepareRecentHistory*(source: PublishedReadyReconciliation,
    config: RecentHistoryConfig): RecentHistoryResult[PreparedRecentHistory] =
  ## Derive original C(3), sealed header, verified guarantees and finalized outputs from one completed post-ready provenance graph.
  template fail(reason: RecentHistoryError) =
    ## Drop private scratch; never expose earlier derived fields after a later refusal.
    return RecentHistoryResult[PreparedRecentHistory](status: reason)
  let ready = source.publishedReadySource
  if ready.error != ReadyReconciliationError.None: fail(RecentHistoryError.InvalidSource)
  let coordinated = ready.value.readyReconciliationSource.value.publishedAccumulationSource.value
  let activity = coordinated.accumulationPublicationSource.value
  let finalized = activity.blockActivitySource.value.serviceActivitySource.value.statisticsSource.value
  let outputs = finalized.finalAccumulationOutputs.value
  let queue = outputs.outputsSource.value.executionRound.value.roundBlockQueue.value
  let admission = queue.accumulationAdmission.value
  let stage = admission.reportBlockStage.value
  if uint64(config.history.cores) != uint64(stage.blockTransitionProfile.cores): fail(
      RecentHistoryError.InvalidConfig)
  let binding = stage.value.admitted
  let header = binding.admittedHeader
  let facts = header.headerInfo.value
  let credentials = admission.reportCredentials.value
  let guarantees = credentials.verifiedGuaranteeCount.value
  let log = outputs.outputsInfo.value
  if uint64(facts.consumed) > uint64(config.headerBytes): fail(RecentHistoryError.LimitExceeded)
  if uint64(log.outputs) > uint64(config.outputs.items) or log.outputs > high(int) div sizeof(AccumulationOutput):
    fail(RecentHistoryError.LimitExceeded) # Bound exact finalized pair extraction before allocation or tree hashing.
  if uint64(log.encodedBytes) > uint64(config.outputs.maxBytes): fail(
      RecentHistoryError.LimitExceeded)
  if uint64(guarantees) > uint64(config.history.perBlock) or uint64(guarantees) > uint64(
      config.history.totalPackages):
    fail(RecentHistoryError.LimitExceeded)
  if uint64(guarantees) > uint64(config.history.cores) or guarantees > high(int) div sizeof(ReportedPackage):
    fail(RecentHistoryError.LimitExceeded) # Newly guaranteed packages, not processed/available reports, populate the new dictionary.
  let parent = binding.admittedState.lookup(chapterKey(StateChapter(3)))
  if parent.error != StateStoreError.None: fail(RecentHistoryError.InvalidState)
  if uint64(parent.value.byteLength) > uint64(config.history.maxBytes): fail(
      RecentHistoryError.LimitExceeded)
  let original = decodeHistoryState(parent.value.bytes, config.history)
  if original.error != HistoryError.None:
    return RecentHistoryResult[PreparedRecentHistory](status: RecentHistoryError.CodecFailure,
        codecReason: original.error)
  if original.value.consumed != parent.value.byteLength: fail(RecentHistoryError.InvalidState)
  var pairs = newSeq[AccumulationOutput](log.outputs)
  for index in 0..<pairs.len: pairs[index] = outputs.outputAt(OutputLogIndex(uint64(index))).value
  var packages = newSeq[ReportedPackage](guarantees)
  for index in 0..<packages.len:
    let report = credentials.verifiedGuaranteeAt(index).value.report.ownedReportInfo.value.header
    packages[index] = ReportedPackage(package: report.packageHash, segment: report.segmentRoot)
  var wire = newSeq[byte](facts.consumed)
  if header.encodeOwnedHeader(wire).error != HeaderError.None: fail(RecentHistoryError.InvalidState)
  let digest = blake2b256(wire)
  if digest.error != CryptoError.None:
    return RecentHistoryResult[PreparedRecentHistory](status: RecentHistoryError.CryptoFailure,
        cryptoReason: digest.error)
  let root = accumulationRoot(pairs, config.outputs)
  if root.error != HistoryTransitionError.None:
    return RecentHistoryResult[PreparedRecentHistory](status: RecentHistoryError.OutputFailure,
        outputReason: root.error)
  let input = HistoryAdvance(header: HistoryHeaderHash(array[32, byte](digest.value)),
    parentState: HistoryStateRoot(array[32, byte](facts.unsigned.priorState)),
    slot: HistorySlot(uint32(facts.unsigned.slot)), accumulation: root.value)
  let advanced = advanceHistory(original.value.snapshot, input, packages, config.history)
  if advanced.error != HistoryTransitionError.None:
    return RecentHistoryResult[PreparedRecentHistory](status: RecentHistoryError.HistoryFailure,
        historyReason: advanced.error)
  let captured = decodeHistoryState(advanced.value.value, config.history)
  if captured.error != HistoryError.None:
    return RecentHistoryResult[PreparedRecentHistory](status: RecentHistoryError.CodecFailure,
        codecReason: captured.error)
  RecentHistoryResult[PreparedRecentHistory](status: RecentHistoryError.None,
    completed: PreparedRecentHistory(data: RecentData(source: source,
      prior: source.publishedReadyState.value,
      entry: advanced.value, snapshot: captured.value.snapshot, info: RecentHistoryInfo(
        header: input.header,
        parentState: input.parentState, slot: input.slot, accumulation: root.value,
        outputs: log.outputs, guarantees: guarantees,
        history: captured.value.snapshot.historyInfo.value))))

proc commit(state: var StateStore, source: PreparedRecentHistory): RecentHistoryResult[
    PublishedRecentHistory] =
  ## Require the exact post-ready prior and publish only the complete C(3) replacement under inherited limits.
  let data = source.data
  if data == nil: return RecentHistoryResult[PublishedRecentHistory](
      status: RecentHistoryError.InvalidSource)
  let current = state.snapshot
  if current.error != StateStoreError.None: return RecentHistoryResult[PublishedRecentHistory](
      status: RecentHistoryError.InvalidState)
  if not sameStateSnapshot(current.value, data.prior): return RecentHistoryResult[
      PublishedRecentHistory](status: RecentHistoryError.ForeignState)
  var working = forkStateStore(data.prior).value
  let entry = data.entry
  let applied = working.apply([StateWrite(key: entry.key, kind: StateWriteKind.Put,
      value: entry.value)])
  if applied.error != StateStoreError.None:
    return RecentHistoryResult[PublishedRecentHistory](status: RecentHistoryError.StateFailure,
        stateReason: applied.error)
  state = working # Sole mutable publication point after complete Merklization.
  RecentHistoryResult[PublishedRecentHistory](status: RecentHistoryError.None,
    completed: PublishedRecentHistory(data: PublishedData(source: source, state: applied.value)))
proc publishRecentHistory*(source: PreparedRecentHistory): RecentHistoryResult[
    PublishedRecentHistory] =
  ## Create a private complete-map successor from the exact retained post-ready stage.
  let data = source.data
  if data == nil: return RecentHistoryResult[PublishedRecentHistory](
      status: RecentHistoryError.InvalidSource)
  var working = forkStateStore(data.prior).value
  commit(working, source)
proc advanceRecentHistory*(state: var StateStore, source: PreparedRecentHistory): RecentHistoryResult[
    PublishedRecentHistory] =
  ## Atomically replace an exact post-ready caller only after successful private history publication.
  commit(state, source)
