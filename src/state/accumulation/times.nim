# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accountspostxfer: set lastAccumulation for surviving accounts in certified S, on a private full map.
## Provides a bounded hash-free projection and an opaque recent-history-bound candidate; C(13) remains separate.

import ../../codec/[bounded, header]
import ../../codec/state/[accounts as state_accounts, statistics as state_statistics,
    layout as state_layout, trie as state_trie]
import ./[recent as accumulation_recent, ready as accumulation_ready,
    history as accumulation_history, statistics as accumulation_statistics,
    finalization as accumulation_finalization, outputs as accumulation_outputs,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue]
import ../report/admission as report_admission
import "../block/transition" as block_transition
import "../block/admission" as block_admission
import ../store

type
  AccumulationTimesLimits* = object ## Bound inspected service keys independently of actual fixed metadata rewrites.
    services*: ElementLimit ## All supplied/certified S keys, including missing or already-current accounts.
    writes*: ElementLimit ## Changed existing records only; missing accounts never authorize creation.
    bytes*: ByteLimit ## Aggregate fixed metadata bytes in changed entries, before allocation.
  AccumulationTimesConfig* = object ## Certified traversal and metadata publication have independent resource policies.
    statistics*: AccumulationStatisticsLimits ## Bounds the exact source-derived S calculation.
    accounts*: AccumulationTimesLimits        ## Bounds key inspection and actual timestamp rewrite storage.
  AccumulationTimesInfo* = object ## Copied observations retain no mutable keys, metadata or snapshot storage.
    slot*: AccountSlot ## Exact candidate slot, or the explicit slot of a pure projection.
    services*, accounts*, absent*, updated*: int ## Inspected S keys, surviving accounts, missing accounts and actual rewrites.
  AccumulationTimeIndex* = distinct uint64 ## Ordinal among changed metadata entries, independent of service identity.
  AccumulationTimesProjection* = object ## Detached entries and copied counts certify no block execution or provenance.
    entries*: seq[StateEntry]    ## Fresh caller-owned metadata encodings; no alias with any source map.
    info*: AccumulationTimesInfo ## Empty and no-change projections remain initialized successes.
  AccumulationTimesError* {.pure.} = enum ## Failed/default outcomes contain only reasons, never partial metadata/state.
    Uninitialized, None, InvalidSource, InvalidState, InvalidIndex, NonCanonical, LimitExceeded,
    StatisticsFailure, MetadataFailure, StateFailure
  TimesData = ref object # Acyclic ownership retains the exact recent candidate and independently derived S.
    source: PreparedAccumulationRecent
    statistics: PreparedAccumulationStatistics
    projection: AccumulationTimesProjection
    state: StateStoreSnapshot
  PreparedAccumulationTimes* = object ## Only the certified constructor creates a full-map timestamp successor.
    data: nil TimesData
  AccumulationTimesResult*[T] = object ## Only success carries values and each nested reason has its own guarded alternative.
    case status: AccumulationTimesError
    of None:
      completed: T # No stale successful metadata on refusal.
    of StatisticsFailure:
      statisticsReason: AccumulationStatisticsError
    of MetadataFailure:
      metadataReason: ServiceMetadataError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # Defaults and policy/shape refusals contain no payload.

func error*[T](outcome: AccumulationTimesResult[T]): AccumulationTimesError =
  ## Read a reason without exposing writable tags.
  outcome.status
func value*[T](outcome: AccumulationTimesResult[T]): T {.inline,
    requires: outcome.status == AccumulationTimesError.None.} =
  ## Extract only selected complete success under checked optimized contracts.
  outcome.completed
func statisticsError*[T](outcome: AccumulationTimesResult[T]): AccumulationStatisticsError {.inline,
    requires: outcome.status == AccumulationTimesError.StatisticsFailure.} =
  ## Inspect only a selected certified-statistics refusal.
  outcome.statisticsReason
func metadataError*[T](outcome: AccumulationTimesResult[T]): ServiceMetadataError {.inline,
    requires: outcome.status == AccumulationTimesError.MetadataFailure.} =
  ## Inspect only a selected fixed metadata codec refusal.
  outcome.metadataReason
func stateError*[T](outcome: AccumulationTimesResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationTimesError.StateFailure.} =
  ## Inspect only a selected private atomic-publication refusal.
  outcome.stateReason

proc projectAccumulationTimes*(prior: StateStoreSnapshot, services: openArray[ServiceIndex],
    slot: AccountSlot, limits: AccumulationTimesLimits): AccumulationTimesResult[
        AccumulationTimesProjection] =
  ## Preflight a stable sorted unique service list and immutable map before allocating detached timestamp writes.
  ## Missing accounts stay absent; already-current metadata is still validated but consumes no write budget.
  template fail(reason: AccumulationTimesError) =
    return AccumulationTimesResult[AccumulationTimesProjection](status: reason)
  if forkStateStore(prior).error != StateStoreError.None:
    fail(AccumulationTimesError.InvalidState) # Validate complete-map initialization without hashing or writes.
  if uint64(services.len) > uint64(limits.services) or services.len > high(int) div sizeof(StateEntry):
    fail(AccumulationTimesError.LimitExceeded) # Work and native entry descriptors are bounded before traversal.
  if services.len > high(int) div sizeof(StateWrite):
    fail(AccumulationTimesError.LimitExceeded) # The later bound adapter must represent the same maximum write set.
  for index in 1..<services.len:
    if uint32(services[index]) <= uint32(services[index-1]):
      fail(AccumulationTimesError.NonCanonical) # Duplicate/disordered keys cannot authorize colliding account writes.
  var info = AccumulationTimesInfo(slot: slot, services: services.len)
  var bytes = 0'u64
  for service in services:
    let found = prior.lookup(chapterServiceKey(StateChapter(255), service))
    if found.error == StateStoreError.MissingKey:
      inc info.absent # Domain intersection does not synthesize accounts that no longer survive.
    else:
      if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
        fail(AccumulationTimesError.InvalidState) # Exact whole-entry framing precedes detached byte extraction.
      let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
      if decoded.error != ServiceMetadataError.None:
        return AccumulationTimesResult[AccumulationTimesProjection](
          status: AccumulationTimesError.MetadataFailure,
          metadataReason: decoded.error) # Invalid metadata never becomes a fabricated zero account.
      inc info.accounts
      if uint32(decoded.value.metadata.lastAccumulation) != uint32(slot):
        if uint64(info.updated) >= uint64(limits.writes):
          fail(AccumulationTimesError.LimitExceeded) # Bound actual rewrites before allocating their descriptors.
        if uint64(ServiceMetadataBytes) > uint64(limits.bytes)-bytes or
            uint64(ServiceMetadataBytes) > uint64(high(int))-bytes:
          fail(AccumulationTimesError.LimitExceeded) # Prove aggregate byte addition under policy and native addressing.
        bytes += uint64(ServiceMetadataBytes)
        inc info.updated # At most the already bounded inspected service count.
  var entries = newSeq[StateEntry](info.updated)
  var cursor = 0
  for service in services:
    let found = prior.lookup(chapterServiceKey(StateChapter(255), service))
    if found.error == StateStoreError.None:
      var metadata = decodeServiceMetadata(found.value.bytes, ByteLimit(
          ServiceMetadataBytes)).value.metadata
      if uint32(metadata.lastAccumulation) != uint32(slot):
        metadata.lastAccumulation = slot # Every other nominal fixed field remains exactly the captured value.
        entries[cursor] = serviceMetadataEntry(service, metadata, ByteLimit(
            ServiceMetadataBytes)).value
        inc cursor # Complete immutable-source preflight proved descriptor and byte extents.
  AccumulationTimesResult[AccumulationTimesProjection](status: AccumulationTimesError.None,
    completed: AccumulationTimesProjection(entries: entries, info: info))

proc accumulationTimesInfo*(plan: PreparedAccumulationTimes): AccumulationTimesResult[
    AccumulationTimesInfo] =
  ## Copy actual source slot, inspected keys, account intersection and rewrite counts.
  let data = plan.data
  if data == nil:
    return AccumulationTimesResult[AccumulationTimesInfo](
        status: AccumulationTimesError.Uninitialized)
  AccumulationTimesResult[AccumulationTimesInfo](status: AccumulationTimesError.None,
      completed: data.projection.info)

proc accumulationTimesSource*(plan: PreparedAccumulationTimes): AccumulationTimesResult[
    PreparedAccumulationRecent] =
  ## Retain exact recent-history and finalized full-map provenance.
  let data = plan.data
  if data == nil:
    return AccumulationTimesResult[PreparedAccumulationRecent](
        status: AccumulationTimesError.Uninitialized)
  AccumulationTimesResult[PreparedAccumulationRecent](status: AccumulationTimesError.None,
      completed: data.source)

proc accumulationTimesStatistics*(plan: PreparedAccumulationTimes): AccumulationTimesResult[
    PreparedAccumulationStatistics] =
  ## Retain the S certificate derived from this source alone, without accepting loose substitute rows.
  let data = plan.data
  if data == nil:
    return AccumulationTimesResult[PreparedAccumulationStatistics](
        status: AccumulationTimesError.Uninitialized)
  AccumulationTimesResult[PreparedAccumulationStatistics](status: AccumulationTimesError.None,
      completed: data.statistics)

proc accumulationTimesState*(plan: PreparedAccumulationTimes): AccumulationTimesResult[
    StateStoreSnapshot] =
  ## Retain the complete private timestamp successor, including earlier chapter and service effects.
  let data = plan.data
  if data == nil:
    return AccumulationTimesResult[StateStoreSnapshot](status: AccumulationTimesError.Uninitialized)
  AccumulationTimesResult[StateStoreSnapshot](status: AccumulationTimesError.None,
      completed: data.state)

proc accumulationTimeEntryAt*(plan: PreparedAccumulationTimes,
    index: AccumulationTimeIndex): AccumulationTimesResult[StateEntry] =
  ## Copy one changed metadata entry at a checked full-width nominal write ordinal.
  let data = plan.data
  if data == nil:
    return AccumulationTimesResult[StateEntry](status: AccumulationTimesError.Uninitialized)
  if uint64(index) >= uint64(data.projection.entries.len):
    return AccumulationTimesResult[StateEntry](status: AccumulationTimesError.InvalidIndex) # Bound before narrowing/access.
  let entry = data.projection.entries[int(uint64(index))]
  var bytes = newSeq[byte](entry.value.len)
  for offset in 0..<bytes.len: bytes[offset] = entry.value[
      offset] # Independent extraction cannot mutate retained entries.
  AccumulationTimesResult[StateEntry](status: AccumulationTimesError.None,
    completed: StateEntry(key: entry.key, value: bytes))

proc prepareAccumulationTimes*(source: PreparedAccumulationRecent,
    config: AccumulationTimesConfig): AccumulationTimesResult[PreparedAccumulationTimes] =
  ## Derive exact S membership and candidate slot, then atomically timestamp only surviving accounts on a private fork.
  template fail(reason: AccumulationTimesError) =
    return AccumulationTimesResult[PreparedAccumulationTimes](status: reason)
  let ready = source.accumulationRecentSource
  if ready.error != AccumulationRecentError.None:
    fail(AccumulationTimesError.InvalidSource) # Defaults cannot fabricate finalization, state or time.
  let finalized = ready.value.accumulationReadySource.value.accumulationHistorySource.value
  let statistics = prepareAccumulationStatistics(finalized, config.statistics)
  if statistics.error != AccumulationStatisticsError.None:
    return AccumulationTimesResult[PreparedAccumulationTimes](
      status: AccumulationTimesError.StatisticsFailure,
      statisticsReason: statistics.error) # Failed traversal carries no partial S rows or metadata.
  let count = statistics.value.statisticsInfo.value.services
  if uint64(count) > uint64(config.accounts.services) or count > high(int) div sizeof(ServiceIndex):
    fail(AccumulationTimesError.LimitExceeded) # Bound S key descriptors before materialization.
  var services = newSeq[ServiceIndex](count)
  for index in 0..<count:
    services[index] = statistics.value.statisticsAt(StatisticsServiceIndex(uint64(
        index))).value.service
  let queue = finalized.finalAccumulationQueue.value
  let binding = queue.accumulationAdmission.value.reportBlockStage.value.value.admitted
  let slot = AccountSlot(uint32(binding.admittedHeader.headerInfo.value.unsigned.slot))
  let prior = source.accumulationRecentState.value
  let projected = projectAccumulationTimes(prior, services, slot, config.accounts)
  if projected.error == AccumulationTimesError.MetadataFailure:
    return AccumulationTimesResult[PreparedAccumulationTimes](
      status: AccumulationTimesError.MetadataFailure,
      metadataReason: projected.metadataError) # Preserve only the selected child cause.
  if projected.error != AccumulationTimesError.None: fail(
      projected.error) # No fork/publication after incomplete preflight.
  var state = prior
  if projected.value.entries.len > 0:
    var writes = newSeq[StateWrite](projected.value.entries.len)
    for index, entry in projected.value.entries:
      writes[index] = StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value)
    var working = forkStateStore(prior).value
    let applied = working.apply(writes)
    if applied.error != StateStoreError.None:
      return AccumulationTimesResult[PreparedAccumulationTimes](
        status: AccumulationTimesError.StateFailure,
        stateReason: applied.error) # The store atomically refuses all timestamp writes and preserves every prior.
    state = applied.value
  AccumulationTimesResult[PreparedAccumulationTimes](status: AccumulationTimesError.None,
    completed: PreparedAccumulationTimes(data: TimesData(source: source,
      statistics: statistics.value,
      projection: projected.value, state: state)))
