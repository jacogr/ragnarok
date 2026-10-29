# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "core_service_activity_arc_release"}

## Literal core/service tuples, distinct report roles, checked sums and independent immutable ARC ownership.

import std/[assertions, syncio]
import ../../../src/state/core/service_activity as core_service_activity
import ../../../src/state/preimages
import ../../../src/codec/[bounded, assurances, report_owned, owned]
import ../../../src/codec/work/[report as work_report, digest as work_digest]
import ../../../src/codec/composite
import ../../../src/codec/state/statistics as state_statistics
import ../../support/arc_evidence

# The entire pure workload runs with both maintained hash backends disabled.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Exact independent populations of the literal mixed fixture.
proc config(): CoreServiceActivityConfig =
  CoreServiceActivityConfig(cores: CoreCount(3), incoming: ElementLimit(2), available: ElementLimit(2),
    digests: ElementLimit(4), assurances: ElementLimit(3), provisions: ElementLimit(3),
    accumulation: ElementLimit(4), services: ElementLimit(7))

# Each refinement measure has its own nonzero literal; authorization/allowance gas are unrelated.
proc load(gas, imports, count, bytes, exports: uint64): RefineLoad =
  RefineLoad(gasUsed: Gas(gas), imports: ImportCount(imports),
      extrinsicCount: work_digest.ExtrinsicCount(count),
    extrinsicSize: work_digest.ExtrinsicBytes(bytes), exports: ExportCount(exports))

# Author a complete canonical report independently of fixtures or protocol statistics code.
proc report(core: int, services: openArray[uint32], loads: openArray[RefineLoad],
    bundle = 7'u32, segments = 0'u16): OwnedReport =
  assert services.len == loads.len and services.len > 0 and services.len <= 16
  var source = WorkReport(core: CoreIndex(uint64(core)), authGas: Gas(high(uint64)),
    digestCount: services.len, authOutput: BlobSpan(offset: 0, length: 0))
  source.header.erasureShards = ErasureShards(6)
  source.header.bundleLength = BundleLength(bundle)
  source.header.segmentCount = SegmentCount(segments)
  for index in 0..<services.len:
    let output = if index mod 2 == 0: successfulWork(BlobSpan(offset: 0, length: 0))
      else: failedWork(WorkKind.OutOfGas) # Failed work still has a refinement observation.
    source.digests[index] = WorkDigest(service: ServiceIndex(services[index]),
      accumulateGas: Gas(high(uint64)), output: output, refine: loads[index])
  var wire = newSeq[byte](4096)
  let written = encodeReportBorrowed(source, [], 341, wire)
  assert written.error == CompositeError.None, "authored report encodes canonically"
  decodeOwnedReport(wire.toOpenArray(0, written.written-1), 341).value

# Raw signed-record fields are structural inputs here; eligibility belongs to the later binding layer.
proc vote(index: uint16, bits: byte): Assurance =
  var value = Assurance(validator: ValidatorIndex(index))
  value.bits.bytes[0] = bits
  value

# S has exactly three allowed fields and requires a nonzero tuple, including transfer-only activity.
proc accumulated(service: uint32, count = 0'u64, transfers = 0'u64,
    gas = 0'u64): ServiceStatisticsEntry =
  var statistics = ServiceActivity(accumulationGas: ActivityGas(gas))
  statistics.counters[ServiceMeasure.AccumulationCount] = ActivityNatural(count)
  statistics.counters[ServiceMeasure.TransferCount] = ActivityNatural(transfers)
  ServiceStatisticsEntry(service: ServiceIndex(service), statistics: statistics)

# All three source populations overlap on some services and leave independent union-only keys.
proc provisions(): seq[PreimageProvision] =
  @[PreimageProvision(service: ServiceIndex(1), count: preimages.ProvisionCount(2),
      bytes: preimages.ProvisionBytes(71)),
    PreimageProvision(service: ServiceIndex(256), count: preimages.ProvisionCount(1),
        bytes: preimages.ProvisionBytes(0)),
    PreimageProvision(service: ServiceIndex(high(uint32)), count: preimages.ProvisionCount(3),
        bytes: preimages.ProvisionBytes(73))]
proc accumulation(): seq[ServiceStatisticsEntry] =
  @[accumulated(0, count = 2), accumulated(42, count = 5, transfers = 7, gas = 59),
    accumulated(257, transfers = 3), accumulated(65536, gas = 61)]
proc incoming(): seq[OwnedReport] =
  @[report(2, [256'u32, 1], [load(11, 2, 3, 5, 7), load(13, 17, 19, 23, 29)], 101, 63),
    report(0, [256'u32, 42], [load(31, 37, 41, 43, 47), default(RefineLoad)], 103, 64)]
proc available(): seq[OwnedReport] =
  let huge = load(high(uint64), high(uint64), high(uint64), high(uint64), high(uint64))
  @[report(2, [999'u32], [huge], 107, 1), report(1, [1000'u32], [huge], 109, 65)]
proc votes(): seq[Assurance] =
  @[vote(1, 5), vote(4, 6), vote(7, 2)]

# Construct the pure owner from scoped independently encoded reports and borrowed arrays.
proc mixed(): CoreServiceActivityProjection =
  var fresh = incoming()
  var newlyAvailable = available()
  var supplied = provisions()
  var used = accumulation()
  var assured = votes()
  result = projectCoreServiceActivity(fresh, newlyAvailable, assured, supplied, used, config()).value
  fresh[0] = default(OwnedReport)
  newlyAvailable[0] = default(OwnedReport)
  supplied[0].count = preimages.ProvisionCount(99)
  used[0] = accumulated(99, gas = 1)
  assured[0].bits.bytes[0] = 0 # Retained rows must be independent from every source population.

# Compare explicit fixed tuples without recomputing the production aggregation formulas.
proc literalWitness() =
  let owner = mixed()
  let info = owner.coreServiceActivityInfo.value
  assert info.cores == 3 and info.incoming == 2 and info.available == 2 and info.digests == 4
  assert info.assurances == 3 and info.provisions == 3 and info.accumulation == 4 and
      info.services == 7
  let coreCounters: array[3, array[7, uint64]] = [
    [0'u64, 1, 37, 41, 43, 47, 103], [275077'u64, 2, 0, 0, 0, 0, 0],
    [8315'u64, 2, 19, 22, 28, 36, 101]]
  let coreGas = [31'u64, 0, 24]
  for core in 0..<3:
    let row = owner.projectedCoreAt(StatisticsCoreIndex(uint64(core))).value
    assert uint64(row.gas) == coreGas[core], "refinement gas excludes authorization and accumulation allowances"
    for measure in low(CoreMeasure)..high(CoreMeasure):
      assert uint64(row.counters[measure]) == coreCounters[core][ord(measure)], "literal per-core field"
  let keys = [0'u32, 1, 42, 256, 257, 65536, high(uint32)]
  let counters: array[7, array[9, uint64]] = [
    [0'u64, 0, 0, 0, 0, 0, 0, 2, 0],
    [2'u64, 71, 1, 17, 19, 23, 29, 0, 0],
    [0'u64, 0, 1, 0, 0, 0, 0, 5, 7],
    [1'u64, 0, 2, 39, 44, 48, 54, 0, 0],
    [0'u64, 0, 0, 0, 0, 0, 0, 0, 3],
    [0'u64, 0, 0, 0, 0, 0, 0, 0, 0],
    [3'u64, 73, 0, 0, 0, 0, 0, 0, 0]]
  let refinementGas = [0'u64, 13, 0, 42, 0, 0, 0]
  let accumulationGas = [0'u64, 0, 59, 0, 0, 61, 0]
  for index in 0..<7:
    let row = owner.projectedServiceAt(StatisticsServiceIndex(uint64(index))).value
    assert uint32(row.service) == keys[index], "numeric service union excludes available-only digests"
    assert uint64(row.statistics.refinementGas) == refinementGas[index], "literal service refinement gas"
    assert uint64(row.statistics.accumulationGas) == accumulationGas[index], "literal S gas field"
    for measure in low(ServiceMeasure)..high(ServiceMeasure):
      assert uint64(row.statistics.counters[measure]) == counters[index][ord(measure)], "literal per-service field"
  var copied = owner.projectedServiceAt(StatisticsServiceIndex(1)).value
  copied.statistics.refinementGas = ActivityGas(0)
  assert uint64(owner.projectedServiceAt(StatisticsServiceIndex(
      1)).value.statistics.refinementGas) == 13,
    "fixed service extraction is independent"
  var core = owner.projectedCoreAt(StatisticsCoreIndex(2)).value
  core.counters[CoreMeasure.Imports] = ActivityNatural(0)
  assert uint64(owner.projectedCoreAt(StatisticsCoreIndex(2)).value.counters[
      CoreMeasure.Imports]) == 19,
    "fixed core extraction is independent"
  var counts = info
  counts.services = 0
  assert owner.coreServiceActivityInfo.value.services == 7, "copied observations cannot change owner"

# Ceiling witnesses are independent literals, particularly 1/63/65 where alternative padding orders differ.
proc availabilityWitnesses() =
  let counts = [0'u16, 1, 63, 64, 65, high(uint16)]
  let expected = [7'u64, 8215, 262663, 266767, 274975, 273158143]
  for index in 0..<counts.len:
    let source = report(0, [99'u32], [default(RefineLoad)], 7, counts[index])
    let owner = projectCoreServiceActivity([], [source], [], [], [], config()).value
    let row = owner.projectedCoreAt(StatisticsCoreIndex(0)).value
    assert uint64(row.counters[CoreMeasure.DataAvailabilityLoad]) == expected[index], "literal padded segment ceiling"
    assert uint64(row.counters[CoreMeasure.BundleBytes]) == 0, "available bundle is DA load only"
    assert owner.coreServiceActivityInfo.value.services == 0, "available work never introduces service keys"
  let full = report(0, [99'u32], [default(RefineLoad)], high(uint32), high(uint16))
  let big = projectCoreServiceActivity([], [full], [], [], [], config()).value
  assert uint64(big.projectedCoreAt(StatisticsCoreIndex(0)).value.counters[
      CoreMeasure.DataAvailabilityLoad]) == 4568125431'u64,
    "full-width header fields are widened before arithmetic"
  var cfg = config()
  cfg.cores = CoreCount(341)
  var last = vote(high(uint16), 0)
  last.bits.bytes[42] = 16
  let raw = projectCoreServiceActivity([], [], [last], [], [], cfg).value
  assert uint64(raw.projectedCoreAt(StatisticsCoreIndex(340)).value.counters[
      CoreMeasure.Popularity]) == 1,
    "raw vote contributes on a reportless last core"
  assert raw.coreServiceActivityInfo.value.services == 0
  last.bits.bytes[42] = 32
  assert projectCoreServiceActivity([], [], [last], [], [], cfg).error ==
      CoreServiceActivityError.NonCanonical,
    "unused bits beyond the largest profile are rejected"

# Select one independent full-width refinement measure, leaving all other additions at zero.
proc measured(field: int, amount: uint64): RefineLoad =
  result = default(RefineLoad)
  case field
  of 0: result.gasUsed = Gas(amount)
  of 1: result.imports = ImportCount(amount)
  of 2: result.extrinsicCount = work_digest.ExtrinsicCount(amount)
  of 3: result.extrinsicSize = work_digest.ExtrinsicBytes(amount)
  else: result.exports = ExportCount(amount)

# One core can overflow across digests; one service can overflow across individually valid cores.
proc overflowWitnesses() =
  for field in 0..<5:
    let almost = measured(field, high(uint64)-1)
    let one = measured(field, 1)
    let two = measured(field, 2)
    let full = measured(field, high(uint64))
    let exactCore = report(0, [42'u32, 43], [almost, one])
    let valid = projectCoreServiceActivity([exactCore], [], [], [], [], config()).value
    let row = valid.projectedCoreAt(StatisticsCoreIndex(0)).value
    if field == 0:
      assert uint64(row.gas) == high(uint64), "exact core gas endpoint"
    else:
      let measure = [CoreMeasure.Imports, CoreMeasure.ExtrinsicCount, CoreMeasure.ExtrinsicBytes,
          CoreMeasure.Exports][field-1]
      assert uint64(row.counters[measure]) == high(uint64), "exact core natural endpoint"
    let excessCore = report(0, [42'u32, 43], [almost, two])
    assert projectCoreServiceActivity([excessCore], [], [], [], [], config()).error ==
        CoreServiceActivityError.CounterOverflow,
      "checked incoming core aggregation"
    let exactService = projectCoreServiceActivity([report(0, [42'u32], [almost]),
      report(1, [42'u32], [one])], [], [], [], [], config()).value
    let service = exactService.projectedServiceAt(StatisticsServiceIndex(0)).value.statistics
    if field == 0:
      assert uint64(service.refinementGas) == high(uint64), "exact service gas endpoint"
    else:
      let measure = [ServiceMeasure.Imports, ServiceMeasure.ExtrinsicCount,
          ServiceMeasure.ExtrinsicBytes, ServiceMeasure.Exports][field-1]
      assert uint64(service.counters[measure]) == high(uint64), "exact service natural endpoint"
    let excessService = projectCoreServiceActivity([report(0, [42'u32], [full]),
      report(1, [42'u32], [one])], [], [], [], [], config())
    assert excessService.error == CoreServiceActivityError.CounterOverflow, "late service overflow across valid cores"
  let provided = PreimageProvision(service: ServiceIndex(42), count: preimages.ProvisionCount(high(uint64)),
    bytes: preimages.ProvisionBytes(high(uint64)))
  let used = accumulated(42, high(uint64), high(uint64), high(uint64))
  let owner = projectCoreServiceActivity([report(0, [42'u32], [default(RefineLoad)])], [], [],
    [provided], [used], config()).value
  let row = owner.projectedServiceAt(StatisticsServiceIndex(0)).value.statistics
  assert uint64(row.counters[ServiceMeasure.ProvisionCount]) == high(uint64)
  assert uint64(row.counters[ServiceMeasure.ProvisionBytes]) == high(uint64)
  assert uint64(row.counters[ServiceMeasure.AccumulationCount]) == high(uint64)
  assert uint64(row.counters[ServiceMeasure.TransferCount]) == high(uint64)
  assert uint64(row.accumulationGas) == high(uint64), "full-width independent contribution fields"

# Reject malformed input families and each independent short policy before returning an owner.
proc refusals() =
  let fresh = incoming()
  let ready = available()
  let assured = votes()
  let supplied = provisions()
  let used = accumulation()
  for mode in 0..<8:
    var cfg = config()
    case mode
    of 0: cfg.incoming = ElementLimit(1)
    of 1: cfg.available = ElementLimit(1)
    of 2: cfg.digests = ElementLimit(3)
    of 3: cfg.assurances = ElementLimit(2)
    of 4: cfg.provisions = ElementLimit(2)
    of 5: cfg.accumulation = ElementLimit(3)
    of 6: cfg.services = ElementLimit(6)
    else: cfg.services = ElementLimit(0)
    assert projectCoreServiceActivity(fresh, ready, assured, supplied, used, cfg).error ==
        CoreServiceActivityError.LimitExceeded,
      "independent short population policy"
  for cores in [0'u64, 1, 342, high(uint64)]:
    var bad = config()
    bad.cores = CoreCount(cores)
    assert projectCoreServiceActivity([], [], [], [], [], bad).error ==
        CoreServiceActivityError.InvalidConfig
  assert projectCoreServiceActivity([default(OwnedReport)], [], [], [], [], config()).error ==
      CoreServiceActivityError.InvalidSource
  assert projectCoreServiceActivity([], [default(OwnedReport)], [], [], [], config()).error ==
      CoreServiceActivityError.InvalidSource
  let foreign = report(3, [42'u32], [default(RefineLoad)])
  assert projectCoreServiceActivity([foreign], [], [], [], [], config()).error ==
      CoreServiceActivityError.InvalidCore
  assert projectCoreServiceActivity([], [foreign], [], [], [], config()).error ==
      CoreServiceActivityError.InvalidCore
  assert projectCoreServiceActivity([fresh[0], fresh[0]], [], [], [], [], config()).error ==
      CoreServiceActivityError.NonCanonical
  assert projectCoreServiceActivity([], [ready[0], ready[0]], [], [], [], config()).error ==
      CoreServiceActivityError.NonCanonical
  for pair in [[vote(1, 1), vote(1, 2)], [vote(2, 1), vote(1, 2)]]:
    assert projectCoreServiceActivity([], [], pair, [], [], config()).error ==
        CoreServiceActivityError.NonCanonical
  for invalid in [vote(0, 8), vote(0, 128)]:
    assert projectCoreServiceActivity([], [], [invalid], [], [], config()).error ==
        CoreServiceActivityError.NonCanonical
  var lateBit = vote(0, 0)
  lateBit.bits.bytes[42] = 1
  assert projectCoreServiceActivity([], [], [lateBit], [], [], config()).error ==
      CoreServiceActivityError.NonCanonical
  for pair in [[supplied[0], supplied[0]], [supplied[1], supplied[0]]]:
    assert projectCoreServiceActivity([], [], [], pair, [], config()).error ==
        CoreServiceActivityError.NonCanonical
  let noItems = PreimageProvision(service: ServiceIndex(1), count: preimages.ProvisionCount(0),
      bytes: preimages.ProvisionBytes(1))
  assert projectCoreServiceActivity([], [], [], [noItems], [], config()).error ==
      CoreServiceActivityError.InvalidContribution
  for pair in [[used[0], used[0]], [used[1], used[0]]]:
    assert projectCoreServiceActivity([], [], [], [], pair, config()).error ==
        CoreServiceActivityError.NonCanonical
  assert projectCoreServiceActivity([], [], [], [], [accumulated(0)], config()).error ==
      CoreServiceActivityError.InvalidContribution
  for measure in ServiceMeasure.ProvisionCount..ServiceMeasure.Exports:
    var invalid = accumulated(42, count = 1)
    invalid.statistics.counters[measure] = ActivityNatural(1)
    assert projectCoreServiceActivity([], [], [], [], [invalid], config()).error ==
        CoreServiceActivityError.InvalidContribution
  var wrongGas = accumulated(42, gas = 1)
  wrongGas.statistics.refinementGas = ActivityGas(1)
  assert projectCoreServiceActivity([], [], [], [], [wrongGas], config()).error ==
      CoreServiceActivityError.InvalidContribution
  var full = config()
  full.incoming = ElementLimit(high(uint64))
  full.available = ElementLimit(high(uint64))
  full.digests = ElementLimit(high(uint64))
  full.assurances = ElementLimit(high(uint64))
  full.provisions = ElementLimit(high(uint64))
  full.accumulation = ElementLimit(high(uint64))
  full.services = ElementLimit(high(uint64))
  assert projectCoreServiceActivity(fresh, ready, assured, supplied, used,
      full).value.coreServiceActivityInfo.value.services == 7,
    "full-width policy maxima never request maximum-sized allocation"
  let owner = mixed()
  for index in [3'u64, high(uint64)]:
    assert owner.projectedCoreAt(StatisticsCoreIndex(index)).error ==
        CoreServiceActivityError.InvalidIndex
  for index in [7'u64, high(uint64)]:
    assert owner.projectedServiceAt(StatisticsServiceIndex(index)).error ==
        CoreServiceActivityError.InvalidIndex
  let defaultOwner = default(CoreServiceActivityProjection)
  assert defaultOwner.coreServiceActivityInfo.error == CoreServiceActivityError.Uninitialized
  assert defaultOwner.projectedCoreAt(StatisticsCoreIndex(0)).error ==
      CoreServiceActivityError.Uninitialized
  assert defaultOwner.projectedServiceAt(StatisticsServiceIndex(0)).error ==
      CoreServiceActivityError.Uninitialized

# Every projected owner/refusal is released before the next occupied-allocation measurement.
proc cycle(fresh, ready: seq[OwnedReport], assured: seq[Assurance], supplied: seq[
    PreimageProvision], used: seq[ServiceStatisticsEntry]) =
  let owner = projectCoreServiceActivity(fresh, ready, assured, supplied, used, config()).value
  assert owner.coreServiceActivityInfo.value.services == 7
  var short = config()
  short.services = ElementLimit(1)
  assert projectCoreServiceActivity(fresh, ready, assured, supplied, used, short).error ==
      CoreServiceActivityError.LimitExceeded

proc main() =
  ## No hash/backend work is allowed in construction, projection, extraction or refusal paths.
  failHash(3)
  literalWitness()
  availabilityWitnesses()
  overflowWitnesses()
  refusals()
  var emptyConfig = config()
  emptyConfig.incoming = ElementLimit(0)
  emptyConfig.available = ElementLimit(0)
  emptyConfig.digests = ElementLimit(0)
  emptyConfig.assurances = ElementLimit(0)
  emptyConfig.provisions = ElementLimit(0)
  emptyConfig.accumulation = ElementLimit(0)
  emptyConfig.services = ElementLimit(0)
  let empty = projectCoreServiceActivity([], [], [], [], [], emptyConfig).value
  assert empty.coreServiceActivityInfo.value.services == 0, "initialized empty per-block projection"
  for core in 0..<3:
    assert empty.projectedCoreAt(StatisticsCoreIndex(uint64(core))).value == default(CoreActivity),
      "fresh block does not carry prior per-block statistics"
  let fresh = incoming()
  let ready = available()
  let assured = votes()
  let supplied = provisions()
  let used = accumulation()
  cycle(fresh, ready, assured, supplied, used)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(fresh, ready, assured, supplied,
      used) # Sources remain fixed; every candidate is scoped.
  let after = getOccupiedMem()
  assert before == after, "core/service activity ARC release"
  assert hashCalls() == 0, "no hash calls in the entire pure suite"
  failHash(0)
  recordArcRelease("core_service_activity", 1000, before, after)
  echo "Core and service activity projection passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

main()
