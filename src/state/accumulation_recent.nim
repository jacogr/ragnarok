# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind GP 0.8.0 recenthistorydef to finalized C(14)/C(15)/C(16), exact sealed header and certified guarantees.
## Reuses history/output algorithms and replaces only C(3) on a private complete-map successor.

import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ../codec/owned as codec_owned
import ../codec/report_owned as codec_report_owned
import ../codec/state_history as codec_state_history
import ../codec/state_outputs as codec_state_outputs
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ../crypto/primitives as crypto_primitives
import ./accumulation_ready as state_accumulation_ready
import ./accumulation_history as state_accumulation_history
import ./accumulation_finalization as state_accumulation_finalization
import ./accumulation_outputs as state_accumulation_outputs
import ./accumulation_execution as state_accumulation_execution
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./guarantee_credentials as state_guarantee_credentials
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./history as state_history
import ./store as state_store

type
  AccumulationRecentConfig* = object ## Independent caller work/encoding policies are checked against actual certified extents.
    headerBytes*: ByteLimit ## Maximum exact sealed header capture before hashing.
    outputs*: OutputLogConfig ## Finalized pair count and canonical log bytes bound root work without recollection.
    history*: HistoryConfig ## Explicit core profile and input/output C(3) row/package/peak/wire policies.
  AccumulationRecentError* {.pure.} = enum ## Defaults and all refusals retain only their selected reason.
    Uninitialized, None, InvalidSource, InvalidConfig, InvalidState, MissingState, LimitExceeded,
    HeaderFailure, BackendFailure, CodecFailure, OutputFailure, HistoryFailure, StateFailure
  RecentData = ref object # Immutable acyclic ownership binds exact predecessor and all completed projections.
    source: PreparedAccumulationReady
    recent: HistorySnapshot
    root: AccumulationRoot
    entry: StateEntry
    state: StateStoreSnapshot
  PreparedAccumulationRecent* = object ## Only source-bound preparation creates this private complete C(3) candidate.
    data: nil RecentData
  AccumulationRecentResult*[T] = object ## Payload and nested stage reasons cannot be extracted under unrelated alternatives.
    case status: AccumulationRecentError
    of None:
      completed: T # Only selected complete success contains application data.
    of HeaderFailure:
      headerReason: HeaderError
    of CodecFailure:
      codecReason: HistoryError
    of OutputFailure, HistoryFailure:
      historyReason: HistoryTransitionError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # No partial header, root, entry or map on refusal.

func error*[T](outcome: AccumulationRecentResult[T]): AccumulationRecentError =
  ## Read a reason without permitting retagging.
  outcome.status
func value*[T](outcome: AccumulationRecentResult[T]): T {.inline,
    requires: outcome.status == AccumulationRecentError.None.} =
  ## Extract only selected complete success under checked optimized contracts.
  outcome.completed
func headerError*[T](outcome: AccumulationRecentResult[T]): HeaderError {.inline,
    requires: outcome.status == AccumulationRecentError.HeaderFailure.} =
  ## Inspect only a selected exact-header encoding refusal.
  outcome.headerReason
func codecError*[T](outcome: AccumulationRecentResult[T]): HistoryError {.inline,
    requires: outcome.status == AccumulationRecentError.CodecFailure.} =
  ## Inspect only a selected recent-history capture refusal.
  outcome.codecReason
func historyError*[T](outcome: AccumulationRecentResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == AccumulationRecentError.HistoryFailure.} =
  ## Inspect only a selected history transition refusal.
  outcome.historyReason
func outputError*[T](outcome: AccumulationRecentResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == AccumulationRecentError.OutputFailure.} =
  ## Inspect only a selected output-root derivation refusal.
  outcome.historyReason
func stateError*[T](outcome: AccumulationRecentResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationRecentError.StateFailure.} =
  ## Inspect only a selected private publication refusal.
  outcome.stateReason

proc accumulationRecentSource*(plan: PreparedAccumulationRecent): AccumulationRecentResult[
    PreparedAccumulationReady] =
  ## Retain the exact ready/history/finalization graph without exposing mutable construction fields.
  let data = plan.data
  if data == nil:
    return AccumulationRecentResult[PreparedAccumulationReady](
        status: AccumulationRecentError.Uninitialized)
  AccumulationRecentResult[PreparedAccumulationReady](status: AccumulationRecentError.None,
      completed: data.source)

proc accumulationRecentHistory*(plan: PreparedAccumulationRecent): AccumulationRecentResult[
    HistorySnapshot] =
  ## Retain the immutable posterior history and its nominal block/package/peak accessors.
  let data = plan.data
  if data == nil:
    return AccumulationRecentResult[HistorySnapshot](status: AccumulationRecentError.Uninitialized)
  AccumulationRecentResult[HistorySnapshot](status: AccumulationRecentError.None,
      completed: data.recent)

proc accumulationRecentRoot*(plan: PreparedAccumulationRecent): AccumulationRecentResult[
    AccumulationRoot] =
  ## Copy the selected complete output-union root appended to the original belt.
  let data = plan.data
  if data == nil:
    return AccumulationRecentResult[AccumulationRoot](status: AccumulationRecentError.Uninitialized)
  AccumulationRecentResult[AccumulationRoot](status: AccumulationRecentError.None,
      completed: data.root)

proc accumulationRecentState*(plan: PreparedAccumulationRecent): AccumulationRecentResult[
    StateStoreSnapshot] =
  ## Retain a complete private map preserving every earlier ready/history/output/service effect.
  let data = plan.data
  if data == nil:
    return AccumulationRecentResult[StateStoreSnapshot](
        status: AccumulationRecentError.Uninitialized)
  AccumulationRecentResult[StateStoreSnapshot](status: AccumulationRecentError.None,
      completed: data.state)

proc accumulationRecentEntry*(plan: PreparedAccumulationRecent): AccumulationRecentResult[StateEntry] =
  ## Copy fresh canonical C(3) bytes independent of retained history and complete state storage.
  let data = plan.data
  if data == nil:
    return AccumulationRecentResult[StateEntry](status: AccumulationRecentError.Uninitialized)
  let entry = data.entry
  var bytes = newSeq[byte](entry.value.len)
  for index in 0..<bytes.len: bytes[index] = entry.value[index] # Copy only the bounded retained encoding.
  AccumulationRecentResult[StateEntry](status: AccumulationRecentError.None,
    completed: StateEntry(key: entry.key, value: bytes))

proc prepareAccumulationRecent*(source: PreparedAccumulationReady,
    config: AccumulationRecentConfig): AccumulationRecentResult[PreparedAccumulationRecent] =
  ## Derive all inputs from genuine finalized ready state and publish C(3) only on a private fork.
  template fail(reason: AccumulationRecentError) =
    return AccumulationRecentResult[PreparedAccumulationRecent](status: reason)
  let accumulated = source.accumulationReadySource
  if accumulated.error != AccumulationReadyError.None:
    fail(AccumulationRecentError.InvalidSource) # Default source cannot fabricate an initialized empty history.
  let finalized = accumulated.value.accumulationHistorySource.value
  let outputs = finalized.finalAccumulationOutputs.value
  let queue = finalized.finalAccumulationQueue.value
  let admission = queue.accumulationAdmission.value
  let stage = admission.reportBlockStage.value
  if uint64(stage.blockTransitionProfile.cores) != uint64(config.history.cores):
    fail(AccumulationRecentError.InvalidConfig) # One authenticated block has exactly one core domain.
  let binding = stage.value.admitted
  let header = binding.admittedHeader
  let metadata = header.headerInfo.value
  let info = outputs.outputsInfo.value
  let credentials = admission.reportCredentials.value
  let count = credentials.verifiedGuaranteeCount.value
  if uint64(metadata.consumed) > uint64(config.headerBytes) or
      uint64(info.outputs) > uint64(config.outputs.items) or uint64(info.encodedBytes) > uint64(
          config.outputs.maxBytes):
    fail(AccumulationRecentError.LimitExceeded) # Bound actual header and complete output-log work before copies/hashes.
  if uint64(count) > uint64(config.history.cores) or uint64(count) > uint64(
      config.history.perBlock):
    fail(AccumulationRecentError.LimitExceeded) # New reports belong to this block's guarantees, never the processed prefix.
  if uint64(count) > uint64(config.history.totalPackages) or count > high(int) div sizeof(ReportedPackage):
    fail(AccumulationRecentError.LimitExceeded) # Prove dictionary descriptor extent before allocation.
  if uint64(count) > uint64(config.history.maxBytes) div 64:
    fail(AccumulationRecentError.LimitExceeded) # Fixed package/segment pairs must fit complete wire policy.
  let prior = source.accumulationReadyState.value
  let stored = prior.lookup(chapterKey(StateChapter(3)))
  if stored.error == StateStoreError.MissingKey: fail(
      AccumulationRecentError.MissingState) # Missing is never genesis.
  if stored.error != StateStoreError.None: fail(AccumulationRecentError.InvalidState) # Require a complete source map.
  if uint64(stored.value.byteLength) > uint64(config.history.maxBytes):
    fail(AccumulationRecentError.LimitExceeded) # Bound detached chapter bytes before extraction.
  let bytes = stored.value.bytes
  let decoded = decodeHistoryState(bytes, config.history)
  if decoded.error != HistoryError.None:
    return AccumulationRecentResult[PreparedAccumulationRecent](
      status: AccumulationRecentError.CodecFailure,
      codecReason: decoded.error) # No hashing or state work after incomplete capture.
  if decoded.value.consumed != bytes.len: fail(AccumulationRecentError.InvalidState) # Reject a valid prefix with suffixes.
  var packages = newSeq[ReportedPackage](count)
  for index in 0..<count:
    let report = credentials.verifiedGuaranteeAt(index).value.report.ownedReportInfo.value
    packages[index] = ReportedPackage(package: report.header.packageHash,
      segment: report.header.segmentRoot) # Both identities come from the same certified report header.
  var headerBytes = newSeq[byte](metadata.consumed)
  let encoded = encodeOwnedHeader(header, headerBytes)
  if encoded.error != HeaderError.None:
    return AccumulationRecentResult[PreparedAccumulationRecent](
      status: AccumulationRecentError.HeaderFailure,
      headerReason: encoded.error) # Never hash partial or unsigned header bytes.
  let hash = blake2b256(headerBytes)
  if hash.error != CryptoError.None: fail(AccumulationRecentError.BackendFailure) # No fabricated header identity.
  let root = outputs.outputsRoot
  if root.error != AccumulationOutputsError.None:
    return AccumulationRecentResult[PreparedAccumulationRecent](
      status: AccumulationRecentError.OutputFailure,
      historyReason: root.historyError) # This initialized owner can refuse only its explicit root derivation.
  let advanced = advanceHistory(decoded.value.snapshot, HistoryAdvance(
    header: HistoryHeaderHash(array[32, byte](hash.value)),
    parentState: HistoryStateRoot(array[32, byte](metadata.unsigned.priorState)),
    slot: HistorySlot(uint32(metadata.unsigned.slot)), accumulation: root.value), packages,
        config.history)
  if advanced.error != HistoryTransitionError.None:
    return AccumulationRecentResult[PreparedAccumulationRecent](
      status: AccumulationRecentError.HistoryFailure,
      historyReason: advanced.error) # Parent correction, belt and canonical history remain one complete projection.
  let captured = decodeHistoryState(advanced.value.value, config.history)
  if captured.error != HistoryError.None:
    return AccumulationRecentResult[PreparedAccumulationRecent](
      status: AccumulationRecentError.CodecFailure,
      codecReason: captured.error) # Retain only complete immutable posterior history.
  var working = forkStateStore(prior).value
  let applied = working.apply([StateWrite(key: advanced.value.key, kind: StateWriteKind.Put,
    value: advanced.value.value)])
  if applied.error != StateStoreError.None:
    return AccumulationRecentResult[PreparedAccumulationRecent](
      status: AccumulationRecentError.StateFailure,
      stateReason: applied.error) # Private backend/resource failure preserves every earlier complete snapshot.
  AccumulationRecentResult[PreparedAccumulationRecent](status: AccumulationRecentError.None,
    completed: PreparedAccumulationRecent(data: RecentData(source: source,
      recent: captured.value.snapshot,
      root: root.value, entry: advanced.value, state: applied.value)))
