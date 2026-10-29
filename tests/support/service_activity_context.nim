# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent per-block service tuples exercise pure and genuine-block refinement/provision/accumulation coordination.

import std/assertions
import ../../src/state/service/activity as service_activity
import ../../src/state/accumulation/[statistics as accumulation_statistics,
    finalization as accumulation_finalization]
import ../../src/state/store
import ../../src/codec/[bounded, composite, owned, report_owned]
import ../../src/codec/work/[report as work_report, digest as work_digest]
import ../../src/codec/state/statistics as state_statistics
import ./report_context

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

proc activityPolicy*(): ServiceActivityConfig =
  ## Small independent work/capture budgets include all source families and retained dictionary rows.
  ServiceActivityConfig(reports: ElementLimit(3), digests: ElementLimit(3), preimages: ElementLimit(3),
    accumulation: ElementLimit(4), services: ElementLimit(4), preimageFrameBytes: ByteLimit(64),
        preimageBytes: ByteLimit(3))
proc activityPreimages*(): seq[byte] =
  ## Three literal canonical records: service 42 has empty/[1,2] blobs and service 77 has [3].
  @[3'u8, 42, 0, 0, 0, 0, 42, 0, 0, 0, 2, 1, 2, 77, 0, 0, 0, 1, 3]
proc widePolicy(): ServiceActivityConfig =
  ## Full-width ceilings constrain actual bounded inputs without becoming allocation sizes themselves.
  ServiceActivityConfig(reports: ElementLimit(high(uint64)), digests: ElementLimit(high(uint64)),
    preimages: ElementLimit(high(uint64)), accumulation: ElementLimit(high(uint64)),
    services: ElementLimit(high(uint64)), preimageFrameBytes: ByteLimit(high(uint64)),
        preimageBytes: ByteLimit(high(uint64)))
proc captured(bytes: seq[byte]): OwnedFrame =
  ## Capture known authored framing; production coordination never reads payload bytes.
  decodeOwnedPreimages(bytes, PreimageLimits(items: ElementLimit(3), perBlob: ByteLimit(2),
      totalBlobBytes: ByteLimit(3))).value
proc incoming(base: OwnedReport, service: uint32, gas = 11'u64, imports = 13'u64,
    failed = false): OwnedReport =
  ## Encode authored independent refinement metrics with the unchanged original borrowed payload owner.
  let raw = reportBytes(base)
  var report = decodeReportBorrowed(raw, 2).value
  report.digestCount = 1
  report.digests[0].service = ServiceIndex(service)
  report.digests[0].refine = RefineLoad(gasUsed: Gas(gas), imports: ImportCount(imports),
    extrinsicCount: work_digest.ExtrinsicCount(17), extrinsicSize: work_digest.ExtrinsicBytes(19),
        exports: ExportCount(23))
  if failed:
    report.digests[0].output = failedWork(WorkKind.Panic) # Failed refinement still contributes its complete usage tuple.
  var bytes = newSeq[byte](raw.len+1024)
  let encoded = encodeReportBorrowed(report, raw, 2, bytes)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(bytes.toOpenArray(0, encoded.written-1), 2).value
proc delta(service: uint32, count, transfers, gas: uint64): ServiceStatisticsEntry =
  ## Author only the three accumulation fields; unrelated activity starts at zero.
  var value = ServiceActivity(accumulationGas: ActivityGas(gas))
  value.counters[ServiceMeasure.AccumulationCount] = ActivityNatural(count)
  value.counters[ServiceMeasure.TransferCount] = ActivityNatural(transfers)
  ServiceStatisticsEntry(service: ServiceIndex(service), statistics: value)
proc sameActivity(left, right: ServiceActivity) =
  ## Compare all eleven fields, including explicit zeros in unrelated families.
  assert uint64(left.refinementGas) == uint64(right.refinementGas)
  assert uint64(left.accumulationGas) == uint64(right.accumulationGas)
  for measure in low(ServiceMeasure)..high(ServiceMeasure):
    assert uint64(left.counters[measure]) == uint64(right.counters[measure])

proc checkActivityProjection*(base: OwnedReport) =
  ## Literal expected tuples distinguish overlap, disjoint services, duplicate reports and empty preimages.
  let a = incoming(base, 42)
  let b = incoming(base, 88, failed = true)
  let provisions = captured(activityPreimages())
  let empty = captured(@[0'u8])
  let accumulation = [delta(42, 2, 3, 7), delta(99, 0, 1, 0)]
  let bigGas = incoming(base, 42, gas = high(uint64))
  let bigImports = incoming(base, 42, imports = high(uint64))
  let wrong = decodeOwnedBytes(@[0'u8], ByteLimit(1)).value
  failHash(3)
  let result = projectServiceActivity([a, b, a], provisions, accumulation, activityPolicy()).value
  assert projectServiceActivity([a, b, a], provisions, accumulation, widePolicy()).value.values.len == 4
  assert result.info.reports == 3 and result.info.digests == 3 and result.info.preimages == 3
  assert result.info.accumulation == 2 and result.info.services == 4
  for index, service in [42'u32, 77'u32, 88'u32, 99'u32]:
    assert uint32(result.values[index].service) == service
  var expected = accumulation[0].statistics
  expected.refinementGas = ActivityGas(22)
  expected.counters[ServiceMeasure.RefinementCount] = ActivityNatural(2)
  expected.counters[ServiceMeasure.Imports] = ActivityNatural(26)
  expected.counters[ServiceMeasure.ExtrinsicCount] = ActivityNatural(34)
  expected.counters[ServiceMeasure.ExtrinsicBytes] = ActivityNatural(38)
  expected.counters[ServiceMeasure.Exports] = ActivityNatural(46)
  expected.counters[ServiceMeasure.ProvisionCount] = ActivityNatural(2)
  expected.counters[ServiceMeasure.ProvisionBytes] = ActivityNatural(2)
  sameActivity(result.values[0].statistics, expected)
  var provided = ServiceActivity()
  provided.counters[ServiceMeasure.ProvisionCount] = ActivityNatural(1)
  provided.counters[ServiceMeasure.ProvisionBytes] = ActivityNatural(1)
  sameActivity(result.values[1].statistics, provided)
  expected = ServiceActivity(refinementGas: ActivityGas(11))
  expected.counters[ServiceMeasure.RefinementCount] = ActivityNatural(1)
  expected.counters[ServiceMeasure.Imports] = ActivityNatural(13)
  expected.counters[ServiceMeasure.ExtrinsicCount] = ActivityNatural(17)
  expected.counters[ServiceMeasure.ExtrinsicBytes] = ActivityNatural(19)
  expected.counters[ServiceMeasure.Exports] = ActivityNatural(23)
  sameActivity(result.values[2].statistics, expected)
  sameActivity(result.values[3].statistics, accumulation[1].statistics)
  for mode in 0..<7:
    var limits = activityPolicy()
    case mode
    of 0: limits.reports = ElementLimit(2) # Bound all incoming report descriptors.
    of 1: limits.digests = ElementLimit(2) # Repeated reports still consume full digest work.
    of 2: limits.preimages = ElementLimit(2) # Empty blobs remain distinct provision records.
    of 3: limits.accumulation = ElementLimit(1) # Bound the independently certified accumulation mapping.
    of 4: limits.services = ElementLimit(3) # All three source families contribute dictionary keys.
    of 5: limits.preimageFrameBytes = ByteLimit(18) # Full encoded capture is 19 bytes.
    else: limits.preimageBytes = ByteLimit(2) # Aggregate actual payload bytes are three.
    assert projectServiceActivity([a, b, a], provisions, accumulation, limits).error ==
        ServiceActivityError.LimitExceeded
  assert projectServiceActivity([bigGas, a], empty, [], activityPolicy()).error ==
      ServiceActivityError.CounterOverflow
  assert projectServiceActivity([bigImports, a], empty, [], activityPolicy()).error ==
      ServiceActivityError.CounterOverflow
  assert uint64(projectServiceActivity([bigGas], empty, [], activityPolicy()).value.values[
      0].statistics.refinementGas) == high(uint64)
  assert projectServiceActivity([default(OwnedReport)], empty, [], activityPolicy()).error ==
      ServiceActivityError.InvalidInput
  for frame in [default(OwnedFrame), wrong]:
    assert projectServiceActivity([], frame, [], activityPolicy()).error ==
        ServiceActivityError.InvalidInput
  for mode in 0..<5:
    var rows = @accumulation
    case mode
    of 0: rows[1].service = ServiceIndex(42) # Duplicate numeric keys cannot masquerade as one accumulation certificate.
    of 1: rows[0].service = ServiceIndex(100) # Descending keys are noncanonical.
    of 2: rows[0].statistics.counters[ServiceMeasure.ProvisionCount] = ActivityNatural(
        1) # Activity families must remain disjoint.
    of 3: rows[0].statistics.refinementGas = ActivityGas(1) # Refiner gas cannot be supplied as accumulation gas.
    else: rows[0].statistics = ServiceActivity() # Omitted zero tuples are not keys of S.
    assert projectServiceActivity([], empty, rows, activityPolicy()).error ==
        ServiceActivityError.InvalidAccumulation
  var zero = activityPolicy()
  zero.reports = ElementLimit(0)
  zero.digests = ElementLimit(0)
  zero.preimages = ElementLimit(0)
  zero.accumulation = ElementLimit(0)
  zero.services = ElementLimit(0)
  assert projectServiceActivity([], empty, [], zero).value.values.len == 0
  assert projectServiceActivity([], empty, [accumulation[1]], activityPolicy()).value.values.len == 1
  assert hashCalls() == 0
  failHash(0)

proc checkServiceActivity*(source: PreparedAccumulationStatistics,
    incoming = false): PreparedServiceActivity =
  ## Genuine block derivation must use incoming guarantees/provisions independently of the accumulated original queue.
  let prior = source.statisticsSource.value.finalAccumulationState.value
  let count = source.statisticsInfo.value.services
  failHash(3)
  let plan = prepareServiceActivity(source, activityPolicy()).value
  assert plan.serviceActivityInfo.value.reports == (if incoming: 1 else: 0)
  assert plan.serviceActivityInfo.value.preimages == (if incoming: 3 else: 0)
  assert plan.serviceActivityInfo.value.accumulation == count
  assert plan.serviceActivityInfo.value.services == count+(if incoming: 1 else: 0)
  for index in 0..<count:
    let original = source.statisticsAt(StatisticsServiceIndex(uint64(index))).value
    let position = if incoming and index == 1: 2 else: index
    let row = plan.serviceActivityAt(StatisticsServiceIndex(uint64(position))).value
    assert uint32(row.service) == uint32(original.service)
    assert uint64(row.statistics.accumulationGas) == uint64(original.statistics.accumulationGas)
    assert uint64(row.statistics.counters[ServiceMeasure.AccumulationCount]) == uint64(
        original.statistics.counters[ServiceMeasure.AccumulationCount])
    assert uint64(row.statistics.counters[ServiceMeasure.TransferCount]) == uint64(
        original.statistics.counters[ServiceMeasure.TransferCount])
    if not incoming: sameActivity(row.statistics, original.statistics)
  if incoming:
    let first = plan.serviceActivityAt(StatisticsServiceIndex(0)).value.statistics
    assert uint64(first.refinementGas) == high(uint64) and uint64(first.counters[
        ServiceMeasure.RefinementCount]) == 1
    assert uint64(first.counters[ServiceMeasure.ProvisionCount]) == 2 and uint64(first.counters[
        ServiceMeasure.ProvisionBytes]) == 2
    let provided = plan.serviceActivityAt(StatisticsServiceIndex(1)).value
    assert uint32(provided.service) == 77 and uint64(provided.statistics.counters[
        ServiceMeasure.ProvisionCount]) == 1
    assert source.statisticsInfo.value.reports == 4 # Incoming report is not drawn from this processed ready queue.
  let copied = plan.serviceActivityAt(StatisticsServiceIndex(0))
  if count != 0:
    var row = copied.value
    row.statistics = ServiceActivity() # Copied row mutation cannot change owner storage.
    sameActivity(plan.serviceActivityAt(StatisticsServiceIndex(0)).value.statistics,
        copied.value.statistics)
  assert prepareServiceActivity(source, widePolicy()).value.serviceActivityInfo.value.services ==
      plan.serviceActivityInfo.value.services
  var shortFrame = activityPolicy()
  shortFrame.preimageFrameBytes = ByteLimit(if incoming: 18'u64 else: 0'u64)
  assert prepareServiceActivity(source, shortFrame).error == ServiceActivityError.LimitExceeded
  var observed = plan.serviceActivityInfo.value
  observed.services = 0
  assert plan.serviceActivityInfo.value.accumulation == count
  assert plan.serviceActivityAt(StatisticsServiceIndex(high(uint64))).error ==
      ServiceActivityError.InvalidIndex
  assert sameStateSnapshot(plan.serviceActivitySource.value.statisticsSource.value.finalAccumulationState.value, prior)
  assert hashCalls() == 0
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareServiceActivity(source, activityPolicy()).value
    assert local.serviceActivityInfo.value.accumulation == count
  assert before == getOccupiedMem() # Captured preimage owners, candidate rows and exact source handles release each cycle.
  assert hashCalls() == 0
  failHash(0)
  plan
