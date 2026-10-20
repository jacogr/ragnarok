# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_statistics_arc_release"}

## Actual finalized histories produce bounded accumulation-only service deltas, including skipped work-items.

import std/[assertions, envvars, syncio]
import ../../../src/state/[service_activity, accumulation_accounts, accumulation_statistics,
  accumulation_finalization, accumulation_outputs,
  accumulation_reentry, accumulation_continuation_execution, accumulation_continuation,
  accumulation_execution,
  accumulation_inputs, accumulation_service, accumulation_dispatch, accumulation_skip, store]
import ../../../src/codec/[bounded, report_owned, state_outputs, state_statistics]
import ../../support/[accumulation_reentry_context, accumulation_execution_context,
  accumulation_continuation_execution_context, accumulation_account_timestamps,
  service_activity_context, arc_evidence]

# Statistics must perform no hashes after genuine signing, execution and private finalization.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Complete only real guests or source-derived non-invoking skips.
proc completed(source: PreparedAccumulationReentry): CompletedAccumulationReentry =
  var runs: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  for index in 0..<source.reentryInputs.value.invocationServiceCount.value:
    let service = prepareReentryAccumulationService(source, InvocationServiceIndex(uint64(index)),
      continuationServiceConfig()).value
    if service.serviceInfo.value.code == AccumulationCodeStatus.Ready:
      runs.add(reentryGuest(source, uint64(index))) # All gas observations come from actual PVM execution.
    else:
      skips.add(finishUninvokedAccumulation(service).value) # Missing code never invents zero-gas executions.
  completeAccumulationReentry(source, runs, skips, executionLimits()).value

# Finalize only after actual guest rounds have reached an idle entry under a finite fixture depth.
proc finished(fixture: ReentryFixture): PreparedFinalAccumulation =
  let limits = AccumulationOutputHistoryLimits(rounds: ElementLimit(6), executions: ElementLimit(10),
    log: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)))
  if not fixture.source.reentryInfo.value.dispatch:
    return prepareFinalAccumulation(fixture.source.reentrySource.value,
        limits).value # Earliest genuine stopped form.
  let policy = executionRoundConfig()
  let config = AccumulationReentryConfig(selection: AccumulationContinuationLimits(
    executions: ElementLimit(2), reports: ElementLimit(4), digests: ElementLimit(8)),
    operands: policy.operands, inputs: policy.inputs)
  var current = fixture.source
  for step in 0..<4:
    let done = completed(current)
    if not current.reentryInfo.value.dispatch:
      return prepareFinalAccumulation(done, limits).value # The exact terminal certificate binds all earlier usage.
    current = prepareAccumulationReentry(done, config, AccumulationReentryDepthLimit(4)).value
  assert false # Authored fixture histories must reach n=0 within their explicit depth budget.
  default(PreparedFinalAccumulation)

# Traversal caps include zeros/skips; the retained service policy applies only after all-zero omission.
proc policy(rounds = 4'u64, gasRows = 6'u64, reports = 4'u64, digests = 6'u64,
    services = 2'u64): AccumulationStatisticsLimits =
  AccumulationStatisticsLimits(rounds: ElementLimit(rounds), gasRows: ElementLimit(gasRows),
    reports: ElementLimit(reports), digests: ElementLimit(digests), services: ElementLimit(services))

# Verify only the accumulation delta is populated, rather than replacing other C(13) activity.
proc checkRow(row: ServiceStatisticsEntry, service: uint32, count, gas: uint64) =
  assert uint32(row.service) == service
  assert uint64(row.statistics.accumulationGas) == gas
  assert uint64(row.statistics.refinementGas) == 0
  for index in 0..<row.statistics.counters.len:
    let measure = ServiceMeasure(index) # The fixed enum-indexed array proves this ordinal is valid.
    let expected = if measure == ServiceMeasure.AccumulationCount: count else: 0'u64
    assert uint64(row.statistics.counters[measure]) ==
        expected # TransferCount and unrelated activity remain zero.

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  checkActivityProjection(base)
  checkAccountProjection() # Pure malformed/missing/current account cases cannot fabricate a block certificate.
  let source = finished(reentryFixture(base))
  failHash(3)
  let plan = prepareAccumulationStatistics(source, policy()).value
  let info = plan.statisticsInfo.value
  assert info.rounds == 4 and info.gasRows == 6
  assert info.reports == 4 and info.digests == 6 and info.services == 2
  assert uint64(info.gasUsed) == 132 # Three actual 22-gas executions of each service, independent of declared reservations.
  checkRow(plan.statisticsAt(StatisticsServiceIndex(0)).value, 42, 4, 66)
  checkRow(plan.statisticsAt(StatisticsServiceIndex(1)).value, 99, 2, 66)
  assert sameStateSnapshot(plan.statisticsSource.value.finalAccumulationState.value,
    source.finalAccumulationState.value)
  assert hashCalls() == 0
  for limits in [policy(rounds = 3), policy(gasRows = 5), policy(reports = 3),
      policy(digests = 5), policy(services = 1), policy(rounds = 0), policy(gasRows = 0),
      policy(reports = 0), policy(digests = 0), policy(services = 0)]:
    assert prepareAccumulationStatistics(source, limits).error ==
        AccumulationStatisticsError.LimitExceeded
  let wide = policy(rounds = high(uint64), gasRows = high(uint64), reports = high(uint64),
    digests = high(uint64), services = high(uint64))
  let fullWidth = prepareAccumulationStatistics(source, wide).value
  checkRow(fullWidth.statisticsAt(StatisticsServiceIndex(1)).value, 99, 2, 66)
  assert plan.statisticsAt(StatisticsServiceIndex(2)).error ==
      AccumulationStatisticsError.InvalidIndex
  assert plan.statisticsAt(StatisticsServiceIndex(high(uint64))).error ==
      AccumulationStatisticsError.InvalidIndex
  var copied = plan.statisticsAt(StatisticsServiceIndex(0)).value
  copied.statistics.accumulationGas = ActivityGas(high(uint64))
  copied.statistics.counters[ServiceMeasure.AccumulationCount] = ActivityNatural(high(uint64))
  checkRow(plan.statisticsAt(StatisticsServiceIndex(0)).value, 42, 4, 66)
  var observed = plan.statisticsInfo.value
  observed.services = high(int)
  assert plan.statisticsInfo.value.services == 2
  let empty = default(PreparedAccumulationStatistics)
  assert empty.statisticsInfo.error == AccumulationStatisticsError.Uninitialized
  assert empty.statisticsSource.error == AccumulationStatisticsError.Uninitialized
  assert empty.statisticsAt(StatisticsServiceIndex(0)).error ==
      AccumulationStatisticsError.Uninitialized
  assert prepareAccumulationStatistics(default(PreparedFinalAccumulation), policy()).error ==
      AccumulationStatisticsError.InvalidSource
  assert hashCalls() == 0
  failHash(0)
  let missing = finished(reentryFixture(base, first = ExecutionEnding.Missing,
    second = ExecutionEnding.Missing))
  let stopped = finished(reentryFixture(base, stopped = true))
  let zero = finished(reentryFixture(base, stopped = true, second = ExecutionEnding.Exhausted))
  let emptySource = finished(reentryFixture(base, empty = true))
  let tail = @[reentryReady(base, 68, [100000'u64, 100000]),
    reentryReady(base, 69, [100000'u64, 100000]), reentryReady(base, 70, [0'u64])]
  let deep = finished(reentryFixture(base, firstGas = 100000, secondGas = 100000, tail = tail))
  failHash(3)
  let skipped = prepareAccumulationStatistics(missing, policy()).value
  assert skipped.statisticsInfo.value.gasRows == 6
  assert uint64(skipped.statisticsInfo.value.gasUsed) == 0
  checkRow(skipped.statisticsAt(StatisticsServiceIndex(0)).value, 42, 4, 0)
  checkRow(skipped.statisticsAt(StatisticsServiceIndex(1)).value, 99, 2, 0)
  let allowance = prepareAccumulationStatistics(stopped, policy(rounds = 2, gasRows = 2,
    reports = 1, digests = 1)).value
  assert allowance.statisticsInfo.value.digests == 1 # Never count work-items in the unaffordable pending suffix.
  assert uint64(allowance.statisticsInfo.value.gasUsed) == 44
  checkRow(allowance.statisticsAt(StatisticsServiceIndex(0)).value, 42, 1, 22)
  checkRow(allowance.statisticsAt(StatisticsServiceIndex(1)).value, 99, 0,
      22) # Allowance-only gas still contributes S(s).
  let omitted = prepareAccumulationStatistics(zero, policy(rounds = 2, gasRows = 2,
    reports = 1, digests = 1, services = 1)).value
  assert omitted.statisticsInfo.value.services == 1 # Service 99 used no gas and accumulated no work-items.
  assert uint64(omitted.statisticsInfo.value.gasUsed) == 22
  checkRow(omitted.statisticsAt(StatisticsServiceIndex(0)).value, 42, 1, 22)
  assert prepareAccumulationStatistics(zero, policy(gasRows = 1)).error ==
      AccumulationStatisticsError.LimitExceeded
  let repeated = prepareAccumulationStatistics(deep, policy(rounds = 6, gasRows = 10,
    reports = 7, digests = 11)).value
  assert repeated.statisticsInfo.value.rounds == 6
  assert repeated.statisticsInfo.value.gasRows == 10
  assert repeated.statisticsInfo.value.reports == 7 and repeated.statisticsInfo.value.digests == 11
  assert uint64(repeated.statisticsInfo.value.gasUsed) == 220
  checkRow(repeated.statisticsAt(StatisticsServiceIndex(0)).value, 42, 7, 110)
  checkRow(repeated.statisticsAt(StatisticsServiceIndex(1)).value, 99, 4, 110)
  let noActivity = prepareAccumulationStatistics(emptySource, policy(rounds = 2, gasRows = 0,
    reports = 0, digests = 0, services = 0)).value
  assert noActivity.statisticsInfo.value.services == 0
  assert noActivity.statisticsInfo.value.reports == 0
  assert uint64(noActivity.statisticsInfo.value.gasUsed) == 0
  assert noActivity.statisticsAt(StatisticsServiceIndex(0)).error ==
      AccumulationStatisticsError.InvalidIndex
  assert hashCalls() == 0
  failHash(0)
  checkAccountTimestamps(plan, [42'u32, 99'u32])
  checkAccountTimestamps(skipped, [42'u32, 99'u32])
  checkAccountTimestamps(allowance, [42'u32, 99'u32])
  checkAccountTimestamps(omitted, [42'u32])
  checkAccountTimestamps(noActivity, [])
  discard checkServiceActivity(plan)
  discard checkServiceActivity(skipped)
  discard checkServiceActivity(noActivity)
  var detachedActivity = default(PreparedServiceActivity)
  block service_activity_callers:
    let local = finished(reentryFixture(base, incomingReports = 1, preimageWire = activityPreimages()))
    let stats = prepareAccumulationStatistics(local, policy()).value
    detachedActivity = checkServiceActivity(stats, incoming = true)
  assert detachedActivity.serviceActivityInfo.value.services == 3
  assert detachedActivity.serviceActivitySource.value.statisticsInfo.value.reports == 4
  var detached: PreparedAccumulationStatistics
  block:
    let local = finished(reentryFixture(base))
    detached = prepareAccumulationStatistics(local, policy()).value
  checkRow(detached.statisticsAt(StatisticsServiceIndex(1)).value, 99, 2, 66)
  assert detached.statisticsSource.value.finalAccumulationInfo.value.pendingReports == 0
  let detachedAccounts = prepareAccumulationAccounts(detached, accountPolicy()).value
  detached = default(PreparedAccumulationStatistics) # The account owner alone now retains this independently built statistics graph.
  assert detachedAccounts.accumulationAccountSource.value.statisticsInfo.value.services == 2
  assert detachedAccounts.accumulationAccountInfo.value.updates == 2
  let before = getOccupiedMem()
  failHash(3)
  for iteration in 0..<1000:
    # Private candidates, compacted records and rejected scratch release while retained source state stays unchanged.
    let plan = prepareAccumulationStatistics(source, policy()).value
    checkRow(plan.statisticsAt(StatisticsServiceIndex(0)).value, 42, 4, 66)
    assert prepareAccumulationStatistics(source, policy(services = 1)).error ==
        AccumulationStatisticsError.LimitExceeded
    assert sameStateSnapshot(plan.statisticsSource.value.finalAccumulationState.value,
      source.finalAccumulationState.value)
  let after = getOccupiedMem()
  assert before == after
  assert hashCalls() == 0
  failHash(0)
  recordArcRelease("accumulation_statistics", 1000, before, after)
  echo "Accumulation statistics passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # I/O and unexpected exceptions remain unsuccessful native executions.
except:
  quit(2)
