# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Coordinate source-derived accumulated-account timestamps, C(15) and C(13) in one atomic batch over finalized accumulation.
## Preparation is hash-free; private and mutable-store publication retain exact full-map identity and inherited limits.

import ../codec/[bounded, composite, header, owned, report_owned, work_report, state_accounts,
  state_workqueues, state_statistics, state_layout, state_trie]
import ./[block_activity, service_activity, accumulation_accounts, accumulation_history,
  accumulation_statistics, accumulation_finalization, accumulation_outputs, accumulation_execution,
  accumulation_round, accumulation_queue, report_admission, block_transition, block_admission, store]

type
  AccumulationPublicationConfig* = object ## Producer limits remain independent of actual final batch population and payload bytes.
    accounts*: AccumulationAccountConfig
    history*: AccumulationHistoryConfig
    writes*: ElementLimit
    writeBytes*: ByteLimit
  PublicationWriteIndex* = distinct uint64 ## Batch ordinal is unrelated to account, core or service dictionary indices.
  AccumulationPublicationInfo* = object ## Copied complete observations expose no mutable projection or batch storage.
    accounts*: AccumulationAccountInfo
    history*: AccumulationHistoryInfo
    activity*: ActivityInfo
    writes*: int
    writeBytes*: uint64
  AccumulationPublicationError* {.pure.} = enum ## Default/refused alternatives contain only selected reasons.
    Uninitialized,       ## Default result or owner.
    None,                ## Complete selected success permits extraction.
    InvalidSource,       ## No genuine complete block activity certificate.
    InvalidState,        ## C(15) or publication store is uninitialized/inexact.
    MissingState,        ## Finalized complete map lacks required C(15).
    InvalidConfig,       ## History policy disagrees with the original source profile.
    InvalidIndex,        ## Full-width batch ordinal is out of range.
    ForeignState,        ## Caller handle is not the exact retained finalized snapshot.
    LimitExceeded,       ## Traversal/capture/final batch exceeds local policy.
    AccountFailure,      ## Inspect the pure account projection refusal.
    MetadataFailure,     ## Inspect the account metadata codec refusal.
    HistoryFailure,      ## Inspect the pure history projection refusal.
    HistoryCodecFailure, ## Inspect exact stored/output history codec refusal.
    StateFailure         ## Inspect atomic store/backend refusal.
  PublicationData = ref object # Acyclic storage binds one source, its exact complete prior and independent batch bytes.
    source: PreparedBlockActivity
    prior: StateStoreSnapshot
    writes: seq[StateWrite]
    info: AccumulationPublicationInfo
  PreparedAccumulationPublication* = object ## Only genuine block activity can authorize this scoped accumulation-stage batch.
    data: nil PublicationData
  PublishedData = ref object # Immutable successor retains the complete preparation graph independently of caller handles.
    source: PreparedAccumulationPublication
    state: StateStoreSnapshot
  PublishedAccumulation* = object ## Private publication does not certify pending ready/recent-history or other block stages.
    data: nil PublishedData
  AccumulationPublicationResult*[T] = object ## Private selected alternatives prevent payload forgery and unrelated reason extraction.
    case status: AccumulationPublicationError
    of None:
      completed: T # Only complete selected success contains values.
    of AccountFailure:
      accountReason: AccumulationAccountError
    of MetadataFailure:
      metadataReason: ServiceMetadataError
    of HistoryFailure:
      historyReason: AccumulationHistoryError
    of HistoryCodecFailure:
      historyCodecReason: WorkQueueError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # No successful prefix, detached batch or partial map survives refusal.

func error*[T](outcome: AccumulationPublicationResult[T]): AccumulationPublicationError =
  ## Inspect the immutable selected reason.
  outcome.status
func value*[T](outcome: AccumulationPublicationResult[T]): T {.inline,
    requires: outcome.status == AccumulationPublicationError.None.} =
  ## Extract complete selected success under checked optimized contracts.
  outcome.completed
func accountError*[T](outcome: AccumulationPublicationResult[T]): AccumulationAccountError {.inline,
    requires: outcome.status == AccumulationPublicationError.AccountFailure.} =
  ## Inspect only a genuine account projection refusal.
  outcome.accountReason
func metadataError*[T](outcome: AccumulationPublicationResult[T]): ServiceMetadataError {.inline,
    requires: outcome.status == AccumulationPublicationError.MetadataFailure.} =
  ## Inspect only a genuine metadata codec failure.
  outcome.metadataReason
func historyError*[T](outcome: AccumulationPublicationResult[T]): AccumulationHistoryError {.inline,
    requires: outcome.status == AccumulationPublicationError.HistoryFailure.} =
  ## Inspect only a genuine history projection refusal.
  outcome.historyReason
func historyCodecError*[T](outcome: AccumulationPublicationResult[T]): WorkQueueError {.inline,
    requires: outcome.status == AccumulationPublicationError.HistoryCodecFailure.} =
  ## Inspect only a stored/output history codec failure.
  outcome.historyCodecReason
func stateError*[T](outcome: AccumulationPublicationResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationPublicationError.StateFailure.} =
  ## Inspect only an atomic publication refusal.
  outcome.stateReason

proc accumulationPublicationInfo*(plan: PreparedAccumulationPublication): AccumulationPublicationResult[
    AccumulationPublicationInfo] =
  ## Copy producer observations and actual batch extent.
  let data = plan.data
  if data == nil: return AccumulationPublicationResult[AccumulationPublicationInfo](
      status: AccumulationPublicationError.Uninitialized)
  AccumulationPublicationResult[AccumulationPublicationInfo](
      status: AccumulationPublicationError.None, completed: data.info)
proc accumulationPublicationSource*(plan: PreparedAccumulationPublication): AccumulationPublicationResult[
    PreparedBlockActivity] =
  ## Retain the exact complete activity provenance after its caller handles retire.
  let data = plan.data
  if data == nil: return AccumulationPublicationResult[PreparedBlockActivity](
      status: AccumulationPublicationError.Uninitialized)
  AccumulationPublicationResult[PreparedBlockActivity](status: AccumulationPublicationError.None,
      completed: data.source)
proc accumulationPublicationPrior*(plan: PreparedAccumulationPublication): AccumulationPublicationResult[
    StateStoreSnapshot] =
  ## Retain the exact finalized complete map required by the mutable-store adapter.
  let data = plan.data
  if data == nil: return AccumulationPublicationResult[StateStoreSnapshot](
      status: AccumulationPublicationError.Uninitialized)
  AccumulationPublicationResult[StateStoreSnapshot](status: AccumulationPublicationError.None,
      completed: data.prior)
proc accumulationPublicationWrite*(plan: PreparedAccumulationPublication,
    index: PublicationWriteIndex): AccumulationPublicationResult[StateWrite] =
  ## Copy one retained mutation after a full-width nominal ordinal check.
  let data = plan.data
  if data == nil: return AccumulationPublicationResult[StateWrite](
      status: AccumulationPublicationError.Uninitialized)
  if uint64(index) >= uint64(data.writes.len):
    return AccumulationPublicationResult[StateWrite](
        status: AccumulationPublicationError.InvalidIndex)
  AccumulationPublicationResult[StateWrite](status: AccumulationPublicationError.None,
      completed: data.writes[int(uint64(index))])
proc publishedAccumulationSource*(plan: PublishedAccumulation): AccumulationPublicationResult[
    PreparedAccumulationPublication] =
  ## Retain the exact batch certificate used to create the successor.
  let data = plan.data
  if data == nil: return AccumulationPublicationResult[PreparedAccumulationPublication](
      status: AccumulationPublicationError.Uninitialized)
  AccumulationPublicationResult[PreparedAccumulationPublication](
      status: AccumulationPublicationError.None, completed: data.source)
proc publishedAccumulationState*(plan: PublishedAccumulation): AccumulationPublicationResult[
    StateStoreSnapshot] =
  ## Retain the immutable complete successor without exposing a mutable store alias.
  let data = plan.data
  if data == nil: return AccumulationPublicationResult[StateStoreSnapshot](
      status: AccumulationPublicationError.Uninitialized)
  AccumulationPublicationResult[StateStoreSnapshot](status: AccumulationPublicationError.None,
      completed: data.state)

proc prepareAccumulationPublication*(source: PreparedBlockActivity,
    config: AccumulationPublicationConfig): AccumulationPublicationResult[
        PreparedAccumulationPublication] =
  ## Derive both pure projections from the complete activity owner's exact accumulation history; never accept sibling candidates.
  template fail(reason: AccumulationPublicationError) =
    ## Drop all bounded scratch without exposing a successful prefix.
    return AccumulationPublicationResult[PreparedAccumulationPublication](status: reason)
  let activity = source.blockActivityInfo
  if activity.error != BlockActivityError.None: fail(AccumulationPublicationError.InvalidSource)
  let statistics = source.blockActivitySource.value.serviceActivitySource.value
  let finalized = statistics.statisticsSource.value
  let initial = finalized.finalAccumulationOutputs.value.outputsSource.value
  let queue = initial.executionRound.value.roundBlockQueue.value
  let stage = queue.accumulationAdmission.value.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  if uint64(config.history.queues.cores) != uint64(profile.cores) or
      uint64(config.history.queues.epochSlots) != uint64(profile.epochSlots):
    fail(AccumulationPublicationError.InvalidConfig) # One authenticated source has one core/epoch domain.
  let count = statistics.statisticsInfo.value.services
  let processed = uint64(finalized.finalAccumulationInfo.value.completedPrefix)
  if uint64(count) > uint64(config.accounts.services) or count > high(int) div sizeof(ServiceIndex):
    fail(AccumulationPublicationError.LimitExceeded) # Bound selected account descriptors before materialization.
  if processed > uint64(config.history.reports) or processed > uint64(high(int) div sizeof(PackageHash)):
    fail(AccumulationPublicationError.LimitExceeded) # Bound all processed report hashes before copying their identities.
  let prior = finalized.finalAccumulationState.value
  var services = newSeq[ServiceIndex](count)
  for index in 0..<count: services[index] = statistics.statisticsAt(StatisticsServiceIndex(uint64(
      index))).value.service
  let slot = AccountSlot(uint32(stage.value.admitted.admittedHeader.headerInfo.value.unsigned.slot))
  let accounts = projectAccumulationAccounts(prior, services, slot, config.accounts)
  if accounts.error == AccumulationAccountError.MetadataFailure:
    return AccumulationPublicationResult[PreparedAccumulationPublication](
        status: AccumulationPublicationError.MetadataFailure,
        metadataReason: accounts.metadataError)
  if accounts.error != AccumulationAccountError.None:
    return AccumulationPublicationResult[PreparedAccumulationPublication](
        status: AccumulationPublicationError.AccountFailure, accountReason: accounts.error)
  let stored = prior.lookup(chapterKey(StateChapter(15)))
  if stored.error == StateStoreError.MissingKey: fail(AccumulationPublicationError.MissingState)
  if stored.error != StateStoreError.None: fail(AccumulationPublicationError.InvalidState)
  if uint64(stored.value.byteLength) > uint64(config.history.queues.maxBytes): fail(
      AccumulationPublicationError.LimitExceeded)
  let raw = stored.value.bytes
  let parent = decodeAccumulatedState(raw, config.history.queues)
  if parent.error != WorkQueueError.None:
    return AccumulationPublicationResult[PreparedAccumulationPublication](
        status: AccumulationPublicationError.HistoryCodecFailure, historyCodecReason: parent.error)
  if parent.value.consumed != raw.len: fail(AccumulationPublicationError.InvalidState)
  var packages = newSeq[PackageHash](int(processed))
  let reports = queue.accumulationProjection.value
  for index in 0..<packages.len:
    packages[index] = reports.accumulationAt(AccumulationIndex(uint64(
        index))).value.ownedReportInfo.value.header.packageHash
  let history = projectAccumulationHistory(parent.value.snapshot, packages, config.history)
  if history.error == AccumulationHistoryError.CodecFailure:
    return AccumulationPublicationResult[PreparedAccumulationPublication](
        status: AccumulationPublicationError.HistoryCodecFailure,
        historyCodecReason: history.codecError)
  if history.error != AccumulationHistoryError.None:
    return AccumulationPublicationResult[PreparedAccumulationPublication](
        status: AccumulationPublicationError.HistoryFailure, historyReason: history.error)
  let activityEntry = source.blockActivityEntry.value
  let historyEntry = history.value.entry
  let changeActivity = prior.lookup(activityEntry.key).value.bytes != activityEntry.value
  let changeHistory = raw != historyEntry.value
  if accounts.value.writes.len > high(int)-2: fail(AccumulationPublicationError.LimitExceeded)
  var writes = accounts.value.writes.len
  for changed in [changeActivity, changeHistory]:
    if changed:
      if writes == high(int): fail(AccumulationPublicationError.LimitExceeded)
      inc writes # Count actual changes; unchanged chapter entries consume no batch budget.
  if uint64(writes) > uint64(config.writes) or writes > high(int) div sizeof(StateWrite):
    fail(AccumulationPublicationError.LimitExceeded)
  var bytes = 0'u64
  for index in 0..<accounts.value.writes.len+2:
    let size = if index < accounts.value.writes.len: accounts.value.writes[index].value.len
      elif index == accounts.value.writes.len: (if changeActivity: activityEntry.value.len else: 0)
      else: (if changeHistory: historyEntry.value.len else: 0) # Independent fixed chapter families cannot duplicate account keys.
    if uint64(size) > uint64(config.writeBytes)-bytes: fail(
        AccumulationPublicationError.LimitExceeded)
    bytes += uint64(size) # Prove every aggregate payload addition before allocating the final batch.
  var batch = newSeq[StateWrite](writes)
  var cursor = 0
  for write in accounts.value.writes:
    batch[cursor] = write
    inc cursor # Pure account projection provides sorted unique changed account keys only.
  for item in [(changeActivity, activityEntry), (changeHistory, historyEntry)]:
    if item[0]:
      let entry = item[1]
      batch[cursor] = StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value)
      inc cursor # C(13)/C(15) are disjoint from C(255) metadata and from each other.
  let ringInfo = history.value.ring.accumulatedInfo.value
  let newest = history.value.ring.accumulatedSlotCount(WorkQueueSlot(uint64(
      ringInfo.slots-1))).value
  AccumulationPublicationResult[PreparedAccumulationPublication](
    status: AccumulationPublicationError.None,
    completed: PreparedAccumulationPublication(data: PublicationData(source: source, prior: prior,
      writes: batch,
      info: AccumulationPublicationInfo(accounts: accounts.value.info, activity: activity.value,
        history: AccumulationHistoryInfo(processedReports: packages.len, newPackages: newest,
          slots: ringInfo.slots, packages: ringInfo.items), writes: writes, writeBytes: bytes))))

proc publishAccumulation*(source: PreparedAccumulationPublication): AccumulationPublicationResult[
    PublishedAccumulation] =
  ## Apply one complete batch privately under inherited map limits, publishing no owner until Merklization succeeds.
  let data = source.data
  if data == nil: return AccumulationPublicationResult[PublishedAccumulation](
      status: AccumulationPublicationError.InvalidSource)
  var working = forkStateStore(data.prior).value
  let applied = working.apply(data.writes)
  if applied.error != StateStoreError.None:
    return AccumulationPublicationResult[PublishedAccumulation](
        status: AccumulationPublicationError.StateFailure, stateReason: applied.error)
  AccumulationPublicationResult[PublishedAccumulation](status: AccumulationPublicationError.None,
    completed: PublishedAccumulation(data: PublishedData(source: source, state: applied.value)))

proc advanceAccumulation*(state: var StateStore, source: PreparedAccumulationPublication): AccumulationPublicationResult[
    PublishedAccumulation] =
  ## Require the exact finalized stage prior, then replace the caller handle once after successful private batch application.
  let data = source.data
  if data == nil: return AccumulationPublicationResult[PublishedAccumulation](
      status: AccumulationPublicationError.InvalidSource)
  let current = state.snapshot
  if current.error != StateStoreError.None: return AccumulationPublicationResult[
      PublishedAccumulation](status: AccumulationPublicationError.InvalidState)
  if not sameStateSnapshot(current.value, data.prior):
    return AccumulationPublicationResult[PublishedAccumulation](
        status: AccumulationPublicationError.ForeignState)
  var working = forkStateStore(data.prior).value
  let applied = working.apply(data.writes)
  if applied.error != StateStoreError.None:
    return AccumulationPublicationResult[PublishedAccumulation](
        status: AccumulationPublicationError.StateFailure, stateReason: applied.error)
  state = working # The sole mutable publication point, after every retained mutation and the root have succeeded.
  AccumulationPublicationResult[PublishedAccumulation](status: AccumulationPublicationError.None,
    completed: PublishedAccumulation(data: PublishedData(source: source, state: applied.value)))
