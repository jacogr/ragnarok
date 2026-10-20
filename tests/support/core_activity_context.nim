# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal core tuples and genuinely signed incoming/available contexts verify independent activity families.

import std/assertions
import ../../src/state/[core_activity, report_admission, guarantee_credentials, block_transition, availability]
import ../../src/codec/[bounded, composite, owned, report_owned, work_report, work_digest,
    state_statistics, assurances]
import ./report_context
import ./report_admission_context

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc corePolicy*(): CoreActivityConfig =
  ## Independently bound every small source population and full original assurance encoding.
  CoreActivityConfig(cores: ElementLimit(341), incoming: ElementLimit(3), available: ElementLimit(3),
    digests: ElementLimit(3), assurances: ElementLimit(6), assuranceBits: ElementLimit(2046),
    assuranceBytes: ByteLimit(4096))
proc authoredCore(base: OwnedReport, core = 0, segments = 1'u16, bundle = 7'u32,
    gas = 11'u64, imports = 13'u64, failed = false): OwnedReport =
  ## Re-encode finite independent refinement metrics; maximum authorization gas must never be counted.
  let raw = reportBytes(base)
  var report = decodeReportBorrowed(raw, 341).value
  report.core = CoreIndex(core)
  report.header.segmentCount = SegmentCount(segments)
  report.header.bundleLength = BundleLength(bundle)
  report.authGas = Gas(high(uint64))
  report.digestCount = 1
  report.digests[0].refine = RefineLoad(gasUsed: Gas(gas), imports: ImportCount(imports),
    extrinsicCount: work_digest.ExtrinsicCount(17), extrinsicSize: work_digest.ExtrinsicBytes(19),
        exports: ExportCount(23))
  if failed: report.digests[0].output = failedWork(WorkKind.Panic) # Failure retains all refinement usage.
  var bytes = newSeq[byte](raw.len+1024)
  let encoded = encodeReportBorrowed(report, raw, 341, bytes)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(bytes.toOpenArray(0, encoded.written-1), 341).value
proc sameCore(left, right: CoreActivity) =
  ## Compare every counter and gas field, including unrelated explicit zeros.
  assert uint64(left.gas) == uint64(right.gas)
  for measure in low(CoreMeasure)..high(CoreMeasure):
    assert uint64(left.counters[measure]) == uint64(right.counters[measure])

proc checkCoreProjection*(base: OwnedReport) =
  ## Independent expected arithmetic covers overlapping/disjoint families and DA rounding discontinuities.
  let a = authoredCore(base)
  let b = authoredCore(base, core = 1, failed = true)
  let maximum = authoredCore(base, segments = high(uint16), bundle = high(uint32))
  let gas = authoredCore(base, gas = high(uint64))
  let imports = authoredCore(base, imports = high(uint64))
  let invalidCore = authoredCore(base, core = 2)
  var vote = Assurance()
  vote.bits.bytes[0] = 3
  var second = Assurance()
  second.bits.bytes[0] = 1
  failHash(3)
  let result = projectCoreActivity(CoreCount(2), [a, b, a], [b], [vote, second], corePolicy()).value
  assert result.info.cores == 2 and result.info.incoming == 3 and result.info.available == 1
  assert result.info.digests == 3 and result.info.assurances == 2
  var expected = CoreActivity(gas: ActivityGas(22))
  for measure, amount in [0'u64, 2, 26, 34, 38, 46, 14]: expected.counters[CoreMeasure(
      measure)] = ActivityNatural(amount)
  sameCore(result.values[0], expected)
  expected = CoreActivity(gas: ActivityGas(11))
  for measure, amount in [8215'u64, 1, 13, 17, 19, 23, 7]: expected.counters[CoreMeasure(
      measure)] = ActivityNatural(amount)
  sameCore(result.values[1], expected)
  failHash(0)
  for index, segments in [0'u16, 1, 63, 64, 65, 65535]:
    let report = authoredCore(base, segments = segments, bundle = 0)
    failHash(3)
    let row = projectCoreActivity(CoreCount(2), [], [report], [], corePolicy()).value.values[0]
    assert uint64(row.counters[CoreMeasure.DataAvailabilityLoad]) == [0'u64, 8208, 262656, 266760,
        274968, 273158136][index]
    assert uint64(row.gas) == 0 # Available reports supply no refinement gas.
    failHash(0)
  failHash(3)
  let maxrow = projectCoreActivity(CoreCount(2), [], [maximum], [], corePolicy()).value.values[0]
  assert uint64(maxrow.counters[CoreMeasure.DataAvailabilityLoad]) == 4568125431'u64
  assert projectCoreActivity(CoreCount(2), [gas, a], [], [], corePolicy()).error ==
      CoreActivityError.CounterOverflow
  assert projectCoreActivity(CoreCount(2), [imports, a], [], [], corePolicy()).error ==
      CoreActivityError.CounterOverflow
  assert uint64(projectCoreActivity(CoreCount(2), [gas], [], [], corePolicy()).value.values[
      0].gas) == high(uint64)
  assert projectCoreActivity(CoreCount(2), [default(OwnedReport)], [], [], corePolicy()).error ==
      CoreActivityError.InvalidInput
  assert projectCoreActivity(CoreCount(2), [], [default(OwnedReport)], [], corePolicy()).error ==
      CoreActivityError.InvalidInput
  assert projectCoreActivity(CoreCount(2), [invalidCore], [], [], corePolicy()).error ==
      CoreActivityError.InvalidCore
  assert projectCoreActivity(CoreCount(2), [], [invalidCore], [], corePolicy()).error ==
      CoreActivityError.InvalidCore
  for count in [0'u64, 1, 342, high(uint64)]:
    assert projectCoreActivity(CoreCount(count), [], [], [], corePolicy()).error ==
        CoreActivityError.InvalidConfig
  for byteIndex in [0, 1, 42]:
    var padding = Assurance()
    padding.bits.bytes[byteIndex] = 4 # Bit2 or wholly unused bytes lie beyond the two-core profile.
    assert projectCoreActivity(CoreCount(2), [], [], [padding], corePolicy()).error ==
        CoreActivityError.InvalidAssurances
  var edge = Assurance()
  edge.bits.bytes[42] = 16 # Core340 is the final valid mainnet bit.
  let edgeRows = projectCoreActivity(CoreCount(341), [], [], [edge], corePolicy()).value.values
  assert edgeRows.len == 341 and uint64(edgeRows[340].counters[CoreMeasure.Popularity]) == 1
  edge.bits.bytes[42] = 32
  assert projectCoreActivity(CoreCount(341), [], [], [edge], corePolicy()).error ==
      CoreActivityError.InvalidAssurances
  for mode in 0..<6:
    var policy = corePolicy()
    case mode
    of 0: policy.cores = ElementLimit(1) # Output profile rows are bounded even for empty activity.
    of 1: policy.incoming = ElementLimit(2) # Every duplicate still consumes descriptor work.
    of 2: policy.available = ElementLimit(0) # DA family has an independent population.
    of 3: policy.digests = ElementLimit(2) # Only incoming digest work counts.
    of 4: policy.assurances = ElementLimit(1) # All original votes count.
    else: policy.assuranceBits = ElementLimit(3) # Two votes times two profile bits require four units.
    assert projectCoreActivity(CoreCount(2), [a, b, a], [b], [vote, second], policy).error ==
        CoreActivityError.LimitExceeded
  var wide = corePolicy()
  wide.cores = ElementLimit(high(uint64))
  wide.incoming = ElementLimit(high(uint64))
  wide.available = ElementLimit(high(uint64))
  wide.digests = ElementLimit(high(uint64))
  wide.assurances = ElementLimit(high(uint64))
  wide.assuranceBits = ElementLimit(high(uint64))
  assert projectCoreActivity(CoreCount(341), [], [], [], wide).value.values.len == 341
  let empty = projectCoreActivity(CoreCount(2), [], [], [], corePolicy()).value
  for row in empty.values: sameCore(row, CoreActivity()) # No old per-block row survives.
  assert hashCalls() == 0
  failHash(0)

proc checkCoreSource*(base: OwnedReport) =
  ## Signed source with incoming and newly available reports proves that the three families stay separate.
  let templateReport = authoredCore(base, segments = 64, bundle = 7)
  var retained = PreparedCoreActivity()
  for mode in 0..<3:
    var signedOptions0 = signedBlockFixtureConfig()
    signedOptions0.reports = (if mode == 2: 0 else: 2)
    signedOptions0.withAvailable = mode != 0
    let context = authored(templateReport, signedOptions0)
    let admission = planBlockReports(context.staged, context.older, config()).value
    failHash(3)
    let plan = prepareCoreActivity(admission, corePolicy()).value
    let info = plan.coreActivityInfo.value
    assert info.cores == 2 and info.incoming == (if mode == 2: 0 else: 2)
    assert info.available == (if mode == 0: 0 else: 1) and info.assurances == (if mode == 0: 0 else: 5)
    for index in 0..<2:
      var expected = CoreActivity()
      if mode != 2:
        expected.gas = ActivityGas(high(uint64)) # Authored admission reports deliberately use maximal refinement gas.
        for measure, amount in [13'u64, 17, 19, 23]: expected.counters[CoreMeasure(ord(
            CoreMeasure.Imports)+measure)] = ActivityNatural(amount)
        expected.counters[CoreMeasure.BundleBytes] = ActivityNatural(7)
      if index == 0 and mode != 0:
        expected.counters[CoreMeasure.DataAvailabilityLoad] = ActivityNatural(266767)
        expected.counters[CoreMeasure.Popularity] = ActivityNatural(5)
      sameCore(plan.coreActivityAt(StatisticsCoreIndex(uint64(index))).value, expected)
    var copy = plan.coreActivityAt(StatisticsCoreIndex(0)).value
    copy.gas = ActivityGas(0)
    assert uint64(plan.coreActivityAt(StatisticsCoreIndex(0)).value.gas) == (if mode ==
        2: 0'u64 else: high(uint64))
    assert plan.coreActivityAt(StatisticsCoreIndex(high(uint64))).error ==
        CoreActivityError.InvalidIndex
    var short = corePolicy()
    short.assuranceBytes = ByteLimit(0)
    assert prepareCoreActivity(admission, short).error == CoreActivityError.LimitExceeded
    let before = getOccupiedMem()
    for iteration in 0..<1000:
      let local = prepareCoreActivity(admission, corePolicy()).value
      assert local.coreActivityInfo.value.available == info.available
    assert before == getOccupiedMem() # Rows, materialized votes and captured source graph retire each cycle.
    assert hashCalls() == 0
    retained = plan
    failHash(0)
  assert retained.coreActivitySource.value.reportCredentials.value.verifiedGuaranteeCount.value == 0
  assert retained.coreActivityInfo.value.available == 1 # Exact source remains alive after local contexts retire.
  assert prepareCoreActivity(default(AdmittedReports), corePolicy()).error ==
      CoreActivityError.InvalidSource
