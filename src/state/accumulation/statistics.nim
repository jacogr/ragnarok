# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive transfer/report accumulation activity from one genuine finalized history, without hashing or writes.
## Exposes immutable accumulation deltas in existing service-statistics records; other activity remains separate.

import std/algorithm
import ../../codec/[bounded, owned, report_owned]
import ../../codec/state/statistics as state_statistics
import ../../codec/work/digest as work_digest
import ./[finalization as accumulation_finalization, outputs as accumulation_outputs,
    reentry as accumulation_reentry]
import ./continuation/[execution as accumulation_continuation_execution,
    inputs as accumulation_continuation_inputs]
import ./[execution as accumulation_execution, inputs as accumulation_inputs,
    round as accumulation_round, queue as accumulation_queue]

type
  AccumulationStatisticsLimits* = object ## Independent ceilings distinguish inspected history from retained nonzero services.
    rounds*: ElementLimit   ## Completed rounds, including idle terminal entries.
    gasRows*: ElementLimit  ## All certified service gas rows, including skips and zeros.
    transfers*: ElementLimit ## All processed records, including duplicate, skipped and zero-gas transfers.
    reports*: ElementLimit  ## Processed original-queue reports inspected for work-items.
    digests*: ElementLimit  ## Total work-digests inspected in that processed prefix.
    services*: ElementLimit ## Retained nonzero accumulation-statistics dictionary entries.
  AccumulationStatisticsInfo* = object ## Copied work and result observations describe exactly one finalized accumulation sequence.
    rounds*, gasRows*, transfers*: int ## Completed history, service rows and processed transfers.
    reports*, digests*, services*: int ## Processed work populations and retained dictionary cardinality.
    gasUsed*: Gas                      ## Gross actual consumption across all completed rounds, bounded by uint64.
  AccumulationStatisticsError* {.pure.} = enum ## Refusals expose no partial rows, source owner or gas totals.
    Uninitialized, ## Default result or statistics owner.
    None,          ## Complete selected success permits extraction.
    InvalidSource, ## No genuine finalization, or certified totals cannot satisfy checked aggregation.
    InvalidIndex,  ## Full-width dictionary ordinal is outside the retained rows.
    UnsupportedTransfers, ## Reserved historical refusal; processed transfers now require an explicit count policy.
    LimitExceeded  ## Traversal, retained dictionary, native scratch or gross Gas representation exceeds policy.
  # Private acyclic ownership retains finalization and fixed independent activity deltas.
  StatisticsData = ref object
    source: PreparedFinalAccumulation
    values: seq[ServiceStatisticsEntry]
    info: AccumulationStatisticsInfo
  PreparedAccumulationStatistics* = object ## Only finalized supported accumulation constructs this immutable delta mapping.
    data: nil StatisticsData
  AccumulationStatisticsResult*[T] = object ## Only selected success carries application data; defaults and refusals carry reasons alone.
    case status: AccumulationStatisticsError
    of None:
      completed: T # Extraction remains guarded in checked optimized builds.
    else:
      discard      # No fabricated empty statistics or partial source survives failure.

func error*[T](outcome: AccumulationStatisticsResult[T]): AccumulationStatisticsError =
  ## Inspect the selected reason without granting mutable discriminator access.
  outcome.status

func value*[T](outcome: AccumulationStatisticsResult[T]): T {.inline,
    requires: outcome.status == AccumulationStatisticsError.None.} =
  ## Extract only complete selected success.
  outcome.completed

proc statisticsInfo*(plan: PreparedAccumulationStatistics): AccumulationStatisticsResult[
    AccumulationStatisticsInfo] =
  ## Copy traversal populations and total actual gas without exposing retained arrays.
  let data = plan.data
  if data == nil:
    return AccumulationStatisticsResult[AccumulationStatisticsInfo](
        status: AccumulationStatisticsError.Uninitialized) # Defaults differ from initialized empty activity.
  AccumulationStatisticsResult[AccumulationStatisticsInfo](status: AccumulationStatisticsError.None,
      completed: data.info)

proc statisticsSource*(plan: PreparedAccumulationStatistics): AccumulationStatisticsResult[
    PreparedFinalAccumulation] =
  ## Retain the exact finalization and its immutable full-state/output history provenance.
  let data = plan.data
  if data == nil:
    return AccumulationStatisticsResult[PreparedFinalAccumulation](
        status: AccumulationStatisticsError.Uninitialized) # No synthesized terminal certificate.
  AccumulationStatisticsResult[PreparedFinalAccumulation](status: AccumulationStatisticsError.None,
      completed: data.source)

proc statisticsAt*(plan: PreparedAccumulationStatistics, index: StatisticsServiceIndex):
    AccumulationStatisticsResult[ServiceStatisticsEntry] =
  ## Copy one numeric-service ordered accumulation delta at a checked nominal dictionary ordinal.
  let data = plan.data
  if data == nil:
    return AccumulationStatisticsResult[ServiceStatisticsEntry](
        status: AccumulationStatisticsError.Uninitialized) # No default service record.
  if uint64(index) >= uint64(data.values.len):
    return AccumulationStatisticsResult[ServiceStatisticsEntry](
        status: AccumulationStatisticsError.InvalidIndex) # Full-width validation precedes native narrowing.
  AccumulationStatisticsResult[ServiceStatisticsEntry](status: AccumulationStatisticsError.None,
      completed: data.values[int(uint64(index))])

proc charge(total: var int, count: int, limit: ElementLimit, rowBytes = sizeof(
    ServiceStatisticsEntry)): bool =
  ## Bound counts and native extents before allocation; rowBytes=1 proves count-only transfer accounting.
  if uint64(count) > uint64(limit)-uint64(total) or count > high(int) div rowBytes-total:
    return false # Earlier successful charges establish both subtraction preconditions.
  total += count
  true

proc appendGas(usage: AccumulationGasUsage, rows: var seq[ServiceStatisticsEntry],
    cursor: var int, total: var uint64, budget: uint64, group: InvocationServiceInfo): bool =
  ## Append one genuine service gas row and its bound destination transfer count into preflighted scratch.
  let gas = uint64(usage.gasUsed)
  if usage.service != group.service or gas > budget-total:
    return false # Prove aggregate arithmetic against actual certified consumption.
  total += gas
  # Complete source coverage pairs each sorted gas row with one exact input group; counts partition the preflighted total.
  var activity = ServiceActivity(accumulationGas: ActivityGas(gas))
  activity.counters[ServiceMeasure.TransferCount] = ActivityNatural(uint64(group.transfers))
  rows[cursor] = ServiceStatisticsEntry(service: usage.service, statistics: activity)
  inc cursor # Complete history preflight proved candidate storage.
  true

func compareService(left, right: ServiceStatisticsEntry): int =
  ## Dictionary order depends only on the numeric service identity, never report or execution arrival order.
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  0

proc prepareAccumulationStatistics*(source: PreparedFinalAccumulation,
    limits: AccumulationStatisticsLimits): AccumulationStatisticsResult[
        PreparedAccumulationStatistics] =
  ## Aggregate processed work-items/transfers and gross actual history gas into bounded service activity deltas.
  template fail(reason: AccumulationStatisticsError) =
    return AccumulationStatisticsResult[PreparedAccumulationStatistics](status: reason)
  let finalized = source.finalAccumulationInfo
  if finalized.error != AccumulationFinalizationError.None:
    fail(AccumulationStatisticsError.InvalidSource) # Only genuine stopped finalization supplies progress and source history.
  let facts = finalized.value
  let rounds = facts.outputs.rounds
  let reentries = rounds-2 # Every supported finalization contains initial and first-continuation completions.
  if uint64(rounds) > uint64(limits.rounds) or reentries > high(int) div sizeof(CompletedAccumulationReentry):
    fail(AccumulationStatisticsError.LimitExceeded) # Bound retained descriptors, including idle rounds, before allocation.
  let processed = uint64(facts.completedPrefix)
  if processed > uint64(limits.reports) or processed > uint64(high(int)):
    fail(AccumulationStatisticsError.LimitExceeded) # Prove report iteration's native extent first.
  let outputs = source.finalAccumulationOutputs.value
  let initial = outputs.outputsSource.value
  let continuation = outputs.outputsContinuation.value
  let queue = initial.executionRound.value.roundBlockQueue.value.accumulationProjection.value
  var completed = newSeq[CompletedAccumulationReentry](reentries)
  if reentries > 0:
    var current = outputs.outputsReentry.value
    for index in 0..<reentries:
      completed[index] = current # Retain only already bounded genuine graph nodes, never caller-supplied batches.
      if index < reentries-1:
        current = current.executionReentry.value.reentryPrevious.value
  var transfers = 0
  if not charge(transfers, continuation.executionInfo.value.round.transfers, limits.transfers, 1):
    fail(AccumulationStatisticsError.LimitExceeded) # Preflight processed records, including zero-gas duplicates.
  for round in completed:
    if not charge(transfers, round.executionInfo.value.round.transfers, limits.transfers, 1):
      fail(AccumulationStatisticsError.LimitExceeded) # Later-only transfers consume the same independent population ceiling.
  var gasRows = 0
  if not charge(gasRows, initial.executionInfo.value.services, limits.gasRows) or
      not charge(gasRows, continuation.executionInfo.value.services, limits.gasRows):
    fail(AccumulationStatisticsError.LimitExceeded) # Skipped services still consume traversal work.
  for round in completed:
    if not charge(gasRows, round.executionInfo.value.services, limits.gasRows):
      fail(AccumulationStatisticsError.LimitExceeded) # No outcome/gas row is read before complete work preflight.
  var digests = 0
  for index in 0..<int(processed):
    let report = queue.accumulationAt(AccumulationIndex(uint64(index))).value
    if not charge(digests, report.ownedReportInfo.value.digestCount, limits.digests):
      fail(AccumulationStatisticsError.LimitExceeded) # Unprocessed reports and their digest counts are never traversed.
  if digests > high(int) div sizeof(ServiceStatisticsEntry)-gasRows:
    fail(AccumulationStatisticsError.LimitExceeded) # Prove combined native row bytes before addition/allocation.
  let initialBudget = uint64(initial.executionInfo.value.round.budget)
  if uint64(facts.remainingGas) > initialBudget:
    fail(AccumulationStatisticsError.InvalidSource) # Genuine paid refunds cannot increase a recursive budget past its initial value.
  var budget = initialBudget-uint64(facts.remainingGas)
  let firstRefund = uint64(continuation.executionInfo.value.round.transferGas)
  if firstRefund > high(uint64)-budget:
    fail(AccumulationStatisticsError.LimitExceeded) # The public aggregate Gas must represent gross usage, not wrapped net consumption.
  budget += firstRefund
  for round in completed:
    let refund = uint64(round.executionInfo.value.round.transferGas)
    if refund > high(uint64)-budget:
      fail(AccumulationStatisticsError.LimitExceeded) # Repeated refunds can exceed uint64 in a valid history; refuse the local representation.
    budget += refund
  var rows = newSeq[ServiceStatisticsEntry](gasRows+digests)
  var cursor = 0
  var total = 0'u64
  let initialInputs = initial.executionRound.value.roundProjection.value.roundInputs.value
  let continuationInputs = continuation.executionContinuation.value.continuationInputs.value
  for index in 0..<initial.executionInfo.value.services:
    if not appendGas(initial.executionGasAt(InvocationServiceIndex(uint64(index))).value,
        rows, cursor, total, budget, initialInputs.invocationServiceAt(InvocationServiceIndex(
            uint64(index))).value):
      fail(AccumulationStatisticsError.InvalidSource) # Initial certified rows consume actual gas once.
  for index in 0..<continuation.executionInfo.value.services:
    if not appendGas(continuation.executionGasAt(InvocationServiceIndex(uint64(index))).value,
        rows, cursor, total, budget, continuationInputs.invocationServiceAt(InvocationServiceIndex(
            uint64(index))).value):
      fail(AccumulationStatisticsError.InvalidSource) # First-continuation rows use the same checked sum.
  for round in completed:
    let inputs = round.executionReentry.value.reentryInputs.value
    for index in 0..<round.executionInfo.value.services:
      if not appendGas(round.executionGasAt(InvocationServiceIndex(uint64(index))).value,
          rows, cursor, total, budget, inputs.invocationServiceAt(InvocationServiceIndex(uint64(
              index))).value):
        fail(AccumulationStatisticsError.InvalidSource) # Each genuine reentry contributes exactly once.
  if total != budget:
    fail(AccumulationStatisticsError.InvalidSource) # Actual round gas must reconcile to net consumption plus every paid outgoing refund.
  for index in 0..<int(processed):
    let report = queue.accumulationAt(AccumulationIndex(uint64(index))).value
    for digest in 0..<report.ownedReportInfo.value.digestCount:
      var activity = ServiceActivity()
      activity.counters[ServiceMeasure.AccumulationCount] = ActivityNatural(1)
      rows[cursor] = ServiceStatisticsEntry(service: report.ownedReportDigest(digest).value.service,
        statistics: activity)
      inc cursor # Preflighted total digest count bounds both the increment and candidate storage.
  rows.sort(compareService)
  var groups = 0
  for index in 0..<rows.len:
    let row = rows[index]
    if groups == 0 or compareService(row, rows[groups-1]) != 0:
      rows[groups] = row
      inc groups # At most one group per bounded candidate.
    else:
      var combined = rows[groups-1]
      let count = uint64(combined.statistics.counters[ServiceMeasure.AccumulationCount]) +
        uint64(row.statistics.counters[ServiceMeasure.AccumulationCount])
      let transferred = uint64(combined.statistics.counters[ServiceMeasure.TransferCount]) +
        uint64(row.statistics.counters[ServiceMeasure.TransferCount])
      let gas = uint64(combined.statistics.accumulationGas) + uint64(row.statistics.accumulationGas)
      combined.statistics.counters[ServiceMeasure.AccumulationCount] = ActivityNatural(count)
      combined.statistics.counters[ServiceMeasure.TransferCount] = ActivityNatural(transferred)
      combined.statistics.accumulationGas = ActivityGas(gas)
      rows[groups-1] = combined # Counts/gas are nonnegative subsets of preflighted digests/transfers and checked gross gas.
  var retained = 0
  for index in 0..<groups:
    let row = rows[index]
    if uint64(row.statistics.counters[ServiceMeasure.AccumulationCount]) != 0 or
        uint64(row.statistics.counters[ServiceMeasure.TransferCount]) != 0 or uint64(
        row.statistics.accumulationGas) != 0:
      if uint64(retained) >= uint64(limits.services):
        fail(AccumulationStatisticsError.LimitExceeded) # Only all-zero S(s) is omitted, after complete aggregation.
      rows[retained] = row
      inc retained
  var values = newSeq[ServiceStatisticsEntry](retained)
  for index in 0..<retained: values[index] = rows[index] # Independent fixed records retain no oversized scratch.
  AccumulationStatisticsResult[PreparedAccumulationStatistics](
    status: AccumulationStatisticsError.None,
    completed: PreparedAccumulationStatistics(data: StatisticsData(source: source, values: values,
      info: AccumulationStatisticsInfo(rounds: rounds, gasRows: gasRows, transfers: transfers,
          reports: int(processed),
        digests: digests, services: retained, gasUsed: Gas(total)))))
