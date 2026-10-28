# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current GP S(s)=(processed work-items, processed incoming transfers, original actual gas) from genuine terminal sequence coverage.
## Complete input groups partition the original contiguous report prefix and accepted transfers, including skipped/absent services.
import std/algorithm
import ../codec/bounded as codec_bounded
import ../codec/state_statistics as codec_state_statistics
import ../codec/work_digest as codec_work_digest
import ./accumulation_current_driver as state_accumulation_current_driver
import ./accumulation_current_sequence as state_accumulation_current_sequence
import ./accumulation_coverage as state_accumulation_coverage
import ./accumulation_annulment as state_accumulation_annulment
import ./accumulation_inputs as state_accumulation_inputs
import ./accumulation_operands as state_accumulation_operands

type
  CurrentAccumulationStatisticsLimits* = object ## Traversal, mathematical counts, retained dictionary and gross gas have independent explicit ceilings.
    entries*, providers*, operands*, transfers*, services*: ElementLimit
    gas*: Gas ## Gross original service gas across entries, not the net budget after outgoing-gas restoration.
  CurrentAccumulationStatisticsInfo* = object ## Fixed copied observations do not claim unrelated refinement/provision activity or final C13 publication.
    entries*, providers*, services*: int
    reports*: AccumulationReportPrefix
    operands*, transfers*: ActivityNatural
    gasUsed*: ActivityGas
  CurrentAccumulationStatisticsError* {.pure.} = enum ## Default/refused alternatives retain no partial rows or unverified source.
    Uninitialized, None, InvalidSource, InvalidIndex, LimitExceeded
  CurrentStatisticsData = ref object # Immutable terminal source and independent fixed dictionary rows share no mutable caller buffers.
    source: CompletedCurrentAccumulationSequence
    values: seq[ServiceStatisticsEntry]
    info: CurrentAccumulationStatisticsInfo
  PreparedCurrentAccumulationStatistics* = object ## Only complete bounded aggregation of genuine sequence providers constructs S.
    data: nil CurrentStatisticsData
  CurrentAccumulationStatisticsResult*[T] = object ## Private reason-only failures cannot masquerade as an initialized empty dictionary.
    case status: CurrentAccumulationStatisticsError
    of None:
      completed: T
    else:
      discard # No partial source, candidate sum or successful prefix survives refusal.

func error*[T](outcome: CurrentAccumulationStatisticsResult[
    T]): CurrentAccumulationStatisticsError =
  ## Inspect the selected reason without permitting mutation.
  outcome.status
func value*[T](outcome: CurrentAccumulationStatisticsResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationStatisticsError.None.} =
  ## Extract only complete selected ownership or fixed observations.
  outcome.completed
proc charge(total: var uint64, count, ceiling: uint64): bool =
  ## Prove mathematical count/gas addition against an explicit unsigned ceiling before updating it.
  if total > ceiling or count > ceiling-total: return false # No wrapped statistic can pass as a smaller valid activity value.
  total += count
  true
func compareService(left, right: ServiceStatisticsEntry): int =
  ## Canonical dictionary order depends only on numeric service identity, never provider/entry arrival.
  cmp(uint32(left.service), uint32(right.service))
proc prepareCurrentAccumulationStatistics*(source: CompletedCurrentAccumulationSequence,
    limits: CurrentAccumulationStatisticsLimits): CurrentAccumulationStatisticsResult[
        PreparedCurrentAccumulationStatistics] =
  ## Fold complete provider groups; each genuine report digest becomes exactly one operand, and every accepted transfer remains counted even without an account.
  template fail(reason: CurrentAccumulationStatisticsError) =
    return CurrentAccumulationStatisticsResult[PreparedCurrentAccumulationStatistics](status: reason)
  let sequence = source.completedSequenceSource
  if sequence.error != CurrentSequenceDriverError.None:
    fail(CurrentAccumulationStatisticsError.InvalidSource) # An active sequence, pure phase or default completion grants no terminal statistics authority.
  let info = sequence.value.currentSequenceInfo.value
  if uint64(info.entries) > uint64(limits.entries):
    fail(CurrentAccumulationStatisticsError.LimitExceeded) # Bound every completed entry before traversing its providers.
  var providers = 0'u64
  var gas = 0'u64
  let maxRows = uint64(high(int) div sizeof(ServiceStatisticsEntry))
  for ordinal in 0..<info.entries:
    let coverage = sequence.value.currentSequenceCoverageAt(CurrentSequenceEntryIndex(uint64(
        ordinal))).value.coverageInfo.value
    let rows = uint64(coverage.services)
    if providers > maxRows or rows > maxRows-providers or not charge(providers, rows, uint64(
        limits.providers)):
      fail(CurrentAccumulationStatisticsError.LimitExceeded) # Prove the whole candidate extent and work sum before allocating.
    if not charge(gas, uint64(coverage.gasUsed), uint64(limits.gas)):
      fail(CurrentAccumulationStatisticsError.LimitExceeded) # Original canceled consumption is retained; gross statistics are not net scheduling budgets.
  var rows = newSeq[ServiceStatisticsEntry](int(providers))
  var cursor = 0
  var operands = 0'u64
  var transfers = 0'u64
  var capturedGas = 0'u64
  for ordinal in 0..<info.entries:
    let coverage = sequence.value.currentSequenceCoverageAt(CurrentSequenceEntryIndex(uint64(
        ordinal))).value
    let inputs = coverage.coverageAnnulment.value.annulmentInputs.value
    let count = coverage.coverageInfo.value.services
    if inputs.invocationServiceCount.value != count:
      fail(CurrentAccumulationStatisticsError.InvalidSource) # Complete provider/group cardinalities are an owned-source invariant.
    for index in 0..<count:
      let row = coverage.coverageRowAt(AccumulationCoverageIndex(uint64(index))).value
      let group = inputs.invocationServiceAt(InvocationServiceIndex(uint64(index))).value
      if uint32(row.service) != uint32(group.service) or not charge(capturedGas, uint64(
          row.gasUsed), gas):
        fail(CurrentAccumulationStatisticsError.InvalidSource) # No detached group or inconsistent original gas can fabricate statistics.
      if not charge(operands, uint64(group.operands), uint64(limits.operands)) or
          not charge(transfers, uint64(group.transfers), uint64(limits.transfers)):
        fail(CurrentAccumulationStatisticsError.LimitExceeded) # Duplicate/zero-value/missing-account transfer records still consume count policy.
      var activity = ServiceActivity(accumulationGas: ActivityGas(uint64(row.gasUsed)))
      activity.counters[ServiceMeasure.AccumulationCount] = ActivityNatural(uint64(group.operands))
      activity.counters[ServiceMeasure.TransferCount] = ActivityNatural(uint64(group.transfers))
      rows[cursor] = ServiceStatisticsEntry(service: row.service, statistics: activity)
      inc cursor # The first pass proves every provider has one bounded independent fixed row.
  if capturedGas != gas:
    fail(CurrentAccumulationStatisticsError.InvalidSource) # Complete row totals must match the certified aggregate before dictionary reduction.
  rows.sort(compareService)
  var groups = 0
  for index in 0..<rows.len:
    let row = rows[index]
    if groups == 0 or uint32(row.service) != uint32(rows[groups-1].service):
      rows[groups] = row
      inc groups # At most one group per preflighted provider row.
    else:
      var combined = rows[groups-1]
      let work = uint64(combined.statistics.counters[ServiceMeasure.AccumulationCount])+uint64(
          row.statistics.counters[ServiceMeasure.AccumulationCount])
      let incoming = uint64(combined.statistics.counters[ServiceMeasure.TransferCount])+uint64(
          row.statistics.counters[ServiceMeasure.TransferCount])
      let consumed = uint64(combined.statistics.accumulationGas)+uint64(
          row.statistics.accumulationGas)
      combined.statistics.counters[ServiceMeasure.AccumulationCount] = ActivityNatural(work)
      combined.statistics.counters[ServiceMeasure.TransferCount] = ActivityNatural(incoming)
      combined.statistics.accumulationGas = ActivityGas(consumed)
      rows[groups-1] = combined # Nonnegative group sums are subsets of the independently preflighted global counts/gas and cannot overflow.
  var retained = 0
  for index in 0..<groups:
    let row = rows[index]
    if uint64(row.statistics.counters[ServiceMeasure.AccumulationCount]) != 0 or
        uint64(row.statistics.counters[ServiceMeasure.TransferCount]) != 0 or uint64(
            row.statistics.accumulationGas) != 0:
      if uint64(retained) >= uint64(limits.services):
        fail(CurrentAccumulationStatisticsError.LimitExceeded) # Only all-zero S is omitted; unavailable/absent/deleted membership never filters activity.
      rows[retained] = row
      inc retained
  var values = newSeq[ServiceStatisticsEntry](retained)
  for index in 0..<retained:
    values[index] = rows[index] # Copy only final fixed rows; caller observations can never mutate the dictionary.
  CurrentAccumulationStatisticsResult[PreparedCurrentAccumulationStatistics](
    status: CurrentAccumulationStatisticsError.None,
    completed: PreparedCurrentAccumulationStatistics(data: CurrentStatisticsData(source: source,
      values: values,
      info: CurrentAccumulationStatisticsInfo(entries: info.entries, providers: int(providers),
          services: retained,
        reports: info.processedReports, operands: ActivityNatural(operands),
            transfers: ActivityNatural(transfers), gasUsed: ActivityGas(gas)))))

proc currentStatisticsInfo*(statistics: PreparedCurrentAccumulationStatistics): CurrentAccumulationStatisticsResult[
    CurrentAccumulationStatisticsInfo] =
  ## Retain complete source-bound statistics; defaults cannot fabricate initialized empty observations.
  let data = statistics.data
  if data == nil:
    return CurrentAccumulationStatisticsResult[CurrentAccumulationStatisticsInfo](
        status: CurrentAccumulationStatisticsError.Uninitialized)
  CurrentAccumulationStatisticsResult[CurrentAccumulationStatisticsInfo](
      status: CurrentAccumulationStatisticsError.None, completed: data.info)

proc currentStatisticsSource*(statistics: PreparedCurrentAccumulationStatistics): CurrentAccumulationStatisticsResult[
    CompletedCurrentAccumulationSequence] =
  ## Retain complete source-bound statistics; defaults cannot fabricate initialized empty observations.
  let data = statistics.data
  if data == nil:
    return CurrentAccumulationStatisticsResult[CompletedCurrentAccumulationSequence](
        status: CurrentAccumulationStatisticsError.Uninitialized)
  CurrentAccumulationStatisticsResult[CompletedCurrentAccumulationSequence](
      status: CurrentAccumulationStatisticsError.None, completed: data.source)

proc currentStatisticsAt*(statistics: PreparedCurrentAccumulationStatistics,
    index: StatisticsServiceIndex): CurrentAccumulationStatisticsResult[ServiceStatisticsEntry] =
  ## Copy one sorted fixed row; full-width ordinals are checked before native narrowing.
  let data = statistics.data
  if data == nil:
    return CurrentAccumulationStatisticsResult[ServiceStatisticsEntry](
        status: CurrentAccumulationStatisticsError.Uninitialized)
  if uint64(index) >= uint64(data.values.len):
    return CurrentAccumulationStatisticsResult[ServiceStatisticsEntry](
        status: CurrentAccumulationStatisticsError.InvalidIndex)
  CurrentAccumulationStatisticsResult[ServiceStatisticsEntry](
      status: CurrentAccumulationStatisticsError.None, completed: data.values[int(uint64(index))])
