# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind current recent history to genuine current C14/C15/C16, exact sealed header and newly guaranteed packages.
## Reuses history/output algorithms and replaces only C(3) on a private complete-map successor.

import ../codec/[bounded, header, owned, report_owned, state_history, state_outputs,
  state_layout, state_trie]
import ../crypto/primitives
import ./[accumulation_current_ready, accumulation_current_finalization,
  accumulation_current_accounts,
  accumulation_current_statistics, accumulation_current_outputs, accumulation_current_driver,
  accumulation_current_sequence, accumulation_current_round, accumulation_block_guests,
  accumulation_recent, accumulation_round, accumulation_queue, report_admission,
  guarantee_credentials, block_transition, block_admission, history, store]

type
  CurrentAccumulationRecentError* {.pure.} = enum ## Defaults and all refusals retain only their selected reason.
    Uninitialized, None, InvalidSource, InvalidConfig, InvalidState, MissingState, LimitExceeded,
    HeaderFailure, BackendFailure, CodecFailure, OutputFailure, HistoryFailure, StateFailure
  CurrentRecentData = ref object # Immutable acyclic ownership binds exact predecessor and all completed projections.
    source: PreparedCurrentAccumulationReady
    recent: HistorySnapshot
    root: AccumulationRoot
    entry: StateEntry
    state: StateStoreSnapshot
  PreparedCurrentAccumulationRecent* = object ## Only source-bound preparation creates this private complete C(3) candidate.
    data: nil CurrentRecentData
  CurrentAccumulationRecentResult*[T] = object ## Payload and nested stage reasons cannot be extracted under unrelated alternatives.
    case status: CurrentAccumulationRecentError
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

func error*[T](outcome: CurrentAccumulationRecentResult[T]): CurrentAccumulationRecentError =
  ## Read a reason without permitting retagging.
  outcome.status
func value*[T](outcome: CurrentAccumulationRecentResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationRecentError.None.} =
  ## Extract only selected complete success under checked optimized contracts.
  outcome.completed
func headerError*[T](outcome: CurrentAccumulationRecentResult[T]): HeaderError {.inline,
    requires: outcome.status == CurrentAccumulationRecentError.HeaderFailure.} =
  ## Inspect only a selected exact-header encoding refusal.
  outcome.headerReason
func codecError*[T](outcome: CurrentAccumulationRecentResult[T]): HistoryError {.inline,
    requires: outcome.status == CurrentAccumulationRecentError.CodecFailure.} =
  ## Inspect only a selected recent-history capture refusal.
  outcome.codecReason
func historyError*[T](outcome: CurrentAccumulationRecentResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == CurrentAccumulationRecentError.HistoryFailure.} =
  ## Inspect only a selected history transition refusal.
  outcome.historyReason
func outputError*[T](outcome: CurrentAccumulationRecentResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == CurrentAccumulationRecentError.OutputFailure.} =
  ## Inspect only a selected output-root derivation refusal.
  outcome.historyReason
func stateError*[T](outcome: CurrentAccumulationRecentResult[T]): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationRecentError.StateFailure.} =
  ## Inspect only a selected private publication refusal.
  outcome.stateReason

proc currentRecentSource*(plan: PreparedCurrentAccumulationRecent): CurrentAccumulationRecentResult[
    PreparedCurrentAccumulationReady] =
  ## Retain the exact ready/history/finalization graph without exposing mutable construction fields.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationRecentResult[PreparedCurrentAccumulationReady](
        status: CurrentAccumulationRecentError.Uninitialized)
  CurrentAccumulationRecentResult[PreparedCurrentAccumulationReady](
      status: CurrentAccumulationRecentError.None, completed: data.source)

proc currentRecentHistory*(plan: PreparedCurrentAccumulationRecent): CurrentAccumulationRecentResult[
    HistorySnapshot] =
  ## Retain the immutable posterior history and its nominal block/package/peak accessors.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationRecentResult[HistorySnapshot](
        status: CurrentAccumulationRecentError.Uninitialized)
  CurrentAccumulationRecentResult[HistorySnapshot](status: CurrentAccumulationRecentError.None,
      completed: data.recent)

proc currentRecentRoot*(plan: PreparedCurrentAccumulationRecent): CurrentAccumulationRecentResult[
    AccumulationRoot] =
  ## Copy the selected complete output-union root appended to the original belt.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationRecentResult[AccumulationRoot](
        status: CurrentAccumulationRecentError.Uninitialized)
  CurrentAccumulationRecentResult[AccumulationRoot](status: CurrentAccumulationRecentError.None,
      completed: data.root)

proc currentRecentState*(plan: PreparedCurrentAccumulationRecent): CurrentAccumulationRecentResult[
    StateStoreSnapshot] =
  ## Retain a complete private map preserving every earlier ready/history/output/service effect.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationRecentResult[StateStoreSnapshot](
        status: CurrentAccumulationRecentError.Uninitialized)
  CurrentAccumulationRecentResult[StateStoreSnapshot](status: CurrentAccumulationRecentError.None,
      completed: data.state)

proc currentRecentEntry*(plan: PreparedCurrentAccumulationRecent): CurrentAccumulationRecentResult[StateEntry] =
  ## Copy fresh canonical C(3) bytes independent of retained history and complete state storage.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationRecentResult[StateEntry](
        status: CurrentAccumulationRecentError.Uninitialized)
  let entry = data.entry
  var bytes = newSeq[byte](entry.value.len)
  for index in 0..<bytes.len: bytes[index] = entry.value[index] # Copy only the bounded retained encoding.
  CurrentAccumulationRecentResult[StateEntry](status: CurrentAccumulationRecentError.None,
    completed: StateEntry(key: entry.key, value: bytes))

proc prepareCurrentAccumulationRecent*(source: PreparedCurrentAccumulationReady,
    config: AccumulationRecentConfig): CurrentAccumulationRecentResult[
        PreparedCurrentAccumulationRecent] =
  ## Derive all inputs from genuine finalized ready state and publish C(3) only on a private fork.
  template fail(reason: CurrentAccumulationRecentError) =
    return CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent](status: reason)
  let finalized = source.currentReadySource
  if finalized.error != CurrentAccumulationReadyError.None:
    fail(CurrentAccumulationRecentError.InvalidSource) # Only current C14 finalization supplies this block's authentic state and completed output.
  let outputs = finalized.value.currentFinalizationOutputs.value
  let completed = finalized.value.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let queue = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value
  let admission = queue.accumulationAdmission.value
  let stage = admission.reportBlockStage.value
  if uint64(stage.blockTransitionProfile.cores) != uint64(config.history.cores):
    fail(CurrentAccumulationRecentError.InvalidConfig) # One authenticated block has exactly one core domain.
  let binding = stage.value.admitted
  let header = binding.admittedHeader
  let metadata = header.headerInfo.value
  let info = outputs.currentOutputsInfo.value
  let credentials = admission.reportCredentials.value
  let count = credentials.verifiedGuaranteeCount.value
  if uint64(metadata.consumed) > uint64(config.headerBytes) or
      uint64(info.outputs) > uint64(config.outputs.items) or uint64(info.encodedBytes) > uint64(
          config.outputs.maxBytes):
    fail(CurrentAccumulationRecentError.LimitExceeded) # Bound actual header and complete output-log work before copies/hashes.
  if uint64(count) > uint64(config.history.cores) or uint64(count) > uint64(
      config.history.perBlock):
    fail(CurrentAccumulationRecentError.LimitExceeded) # New reports belong to this block's guarantees, never the processed prefix.
  if uint64(count) > uint64(config.history.totalPackages) or count > high(int) div sizeof(ReportedPackage):
    fail(CurrentAccumulationRecentError.LimitExceeded) # Prove dictionary descriptor extent before allocation.
  if uint64(count) > uint64(config.history.maxBytes) div 64:
    fail(CurrentAccumulationRecentError.LimitExceeded) # Fixed package/segment pairs must fit complete wire policy.
  let prior = source.currentReadyState.value
  let stored = prior.lookup(chapterKey(StateChapter(3)))
  if stored.error == StateStoreError.MissingKey: fail(
      CurrentAccumulationRecentError.MissingState) # Missing is never genesis.
  if stored.error != StateStoreError.None: fail(CurrentAccumulationRecentError.InvalidState) # Require a complete source map.
  if uint64(stored.value.byteLength) > uint64(config.history.maxBytes):
    fail(CurrentAccumulationRecentError.LimitExceeded) # Bound detached chapter bytes before extraction.
  let bytes = stored.value.bytes
  let decoded = decodeHistoryState(bytes, config.history)
  if decoded.error != HistoryError.None:
    return CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent](
      status: CurrentAccumulationRecentError.CodecFailure,
      codecReason: decoded.error) # No hashing or state work after incomplete capture.
  if decoded.value.consumed != bytes.len: fail(CurrentAccumulationRecentError.InvalidState) # Reject a valid prefix with suffixes.
  var packages = newSeq[ReportedPackage](count)
  for index in 0..<count:
    let report = credentials.verifiedGuaranteeAt(index).value.report.ownedReportInfo.value
    packages[index] = ReportedPackage(package: report.header.packageHash,
      segment: report.header.segmentRoot) # Both identities come from the same certified report header.
  var headerBytes = newSeq[byte](metadata.consumed)
  let encoded = encodeOwnedHeader(header, headerBytes)
  if encoded.error != HeaderError.None:
    return CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent](
      status: CurrentAccumulationRecentError.HeaderFailure,
      headerReason: encoded.error) # Never hash partial or unsigned header bytes.
  let hash = blake2b256(headerBytes)
  if hash.error != CryptoError.None: fail(CurrentAccumulationRecentError.BackendFailure) # No fabricated header identity.
  let root = outputs.currentOutputsRoot
  if root.error != CurrentAccumulationOutputsError.None:
    return CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent](
      status: CurrentAccumulationRecentError.OutputFailure,
      historyReason: root.historyFailure) # This initialized owner can refuse only its explicit root derivation.
  let advanced = advanceHistory(decoded.value.snapshot, HistoryAdvance(
    header: HistoryHeaderHash(array[32, byte](hash.value)),
    parentState: HistoryStateRoot(array[32, byte](metadata.unsigned.priorState)),
    slot: HistorySlot(uint32(metadata.unsigned.slot)), accumulation: root.value), packages,
        config.history)
  if advanced.error != HistoryTransitionError.None:
    return CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent](
      status: CurrentAccumulationRecentError.HistoryFailure,
      historyReason: advanced.error) # Parent correction, belt and canonical history remain one complete projection.
  let captured = decodeHistoryState(advanced.value.value, config.history)
  if captured.error != HistoryError.None:
    return CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent](
      status: CurrentAccumulationRecentError.CodecFailure,
      codecReason: captured.error) # Retain only complete immutable posterior history.
  var working = forkStateStore(prior).value
  let applied = working.apply([StateWrite(key: advanced.value.key, kind: StateWriteKind.Put,
    value: advanced.value.value)])
  if applied.error != StateStoreError.None:
    return CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent](
      status: CurrentAccumulationRecentError.StateFailure,
      stateReason: applied.error) # Private backend/resource failure preserves every earlier complete snapshot.
  CurrentAccumulationRecentResult[PreparedCurrentAccumulationRecent](
    status: CurrentAccumulationRecentError.None,
    completed: PreparedCurrentAccumulationRecent(data: CurrentRecentData(source: source,
      recent: captured.value.snapshot,
      root: root.value, entry: advanced.value, state: applied.value)))
