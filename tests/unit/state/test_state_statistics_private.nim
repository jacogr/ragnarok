import ../../support/arc_evidence
## Project-only ownership, copied statistics, selector and arithmetic checks; no private runtime hooks.
import std/[assertions, syncio]
include ../../../src/codec/state_statistics

## Independent current/previous populations model a resized epoch with bounded core/service work.
proc policy(): ActivityConfig =
  ActivityConfig(cores: CoreCount(3), current: ValidatorCount(6), previous: ValidatorCount(9),
    maxServices: ElementLimit(2), maxBytes: ByteLimit(2000))

## Author all three families directly, retaining E4 counters and the full compact natural/gas domain.
proc source(marker: uint32): ActivityState =
  result = default(ActivityState)
  result.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](6)
  result.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](9)
  result.validators[StatisticsEpoch.Current][0][ValidatorMeasure.Blocks] = ValidatorCounter(marker)
  result.validators[StatisticsEpoch.Previous][8][ValidatorMeasure.Assurances] = ValidatorCounter(
      high(uint32))
  result.cores = newSeq[CoreActivity](3)
  result.cores[2].counters[CoreMeasure.BundleBytes] = ActivityNatural(marker)
  result.cores[2].gas = ActivityGas(high(uint64))
  var first = ServiceStatisticsEntry(service: ServiceIndex(255))
  first.statistics.refinementGas = ActivityGas(128)
  first.statistics.accumulationGas = ActivityGas(high(uint64))
  first.statistics.counters[ServiceMeasure.TransferCount] = ActivityNatural(marker)
  result.services = @[first, ServiceStatisticsEntry(service: ServiceIndex(256))]

## Return only immutable private copies after local typed sources, entry and caller wire retire.
proc escaped(marker: uint32): ActivitySnapshot =
  var original = source(marker)
  let entry = activityStateEntry(original, policy())
  assert entry.error == ActivityError.None
  var wire = entry.value.value
  let parsed = decodeActivityState(wire, policy())
  assert parsed.error == ActivityError.None
  result = parsed.value.snapshot
  original = default(ActivityState)
  # Retained records must survive destruction of every input byte.
  for i in 0..<wire.len: wire[i] = 0

## Each scope retires replaced/retained owners, every fixed family copy and late rejected temporaries.
proc cycle() =
  var owner = escaped(17)
  let alias = owner
  owner = escaped(29)
  assert uint32(validatorActivityAt(alias, StatisticsEpoch.Current, StatisticsValidatorIndex(
      0)).value[ValidatorMeasure.Blocks]) == 17
  assert uint64(coreActivityAt(owner, StatisticsCoreIndex(2)).value.counters[
      CoreMeasure.BundleBytes]) == 29
  assert uint32(validatorActivityAt(alias, StatisticsEpoch.Previous, StatisticsValidatorIndex(
      8)).value[ValidatorMeasure.Assurances]) == high(uint32)
  var info = activityInfo(alias).value
  info.validators[StatisticsEpoch.Previous] = 0
  info.services = 0
  assert activityInfo(alias).value.validators[StatisticsEpoch.Previous] == 9
  var validator = validatorActivityAt(alias, StatisticsEpoch.Current, StatisticsValidatorIndex(0)).value
  validator[ValidatorMeasure.Blocks] = ValidatorCounter(0)
  assert uint32(validatorActivityAt(alias, StatisticsEpoch.Current, StatisticsValidatorIndex(
      0)).value[ValidatorMeasure.Blocks]) == 17
  var core = coreActivityAt(alias, StatisticsCoreIndex(2)).value
  core.gas = ActivityGas(0)
  assert uint64(coreActivityAt(alias, StatisticsCoreIndex(2)).value.gas) == high(uint64)
  var service = serviceActivityAt(alias, StatisticsServiceIndex(0)).value
  service.service = ServiceIndex(0)
  service.statistics = default(ServiceActivity)
  assert uint32(serviceActivityAt(alias, StatisticsServiceIndex(0)).value.service) == 255
  assert uint64(serviceActivityAt(alias, StatisticsServiceIndex(
      0)).value.statistics.accumulationGas) == high(uint64)
  owner = default(ActivitySnapshot)
  assert activityInfo(owner).error == ActivityError.InvalidOwner
  assert activityInfo(alias).value.services == 2
  assert validatorActivityAt(alias, StatisticsEpoch(255), StatisticsValidatorIndex(0)).error ==
      ActivityError.InvalidTag
  assert validatorActivityAt(alias, StatisticsEpoch.Current, StatisticsValidatorIndex(8)).error ==
      ActivityError.InvalidIndex
  assert coreActivityAt(alias, StatisticsCoreIndex(high(uint64))).error ==
      ActivityError.InvalidIndex
  assert serviceActivityAt(alias, StatisticsServiceIndex(high(uint64))).error ==
      ActivityError.InvalidIndex
  let original = source(43)
  let entry = activityStateEntry(original, policy())
  var wire = newSeq[byte](entry.value.value.len+1)
  # Replace the last zero accumulation-gas field with a complete overlong representation after all earlier fields.
  for i in 0..<entry.value.value.len-1: wire[i] = entry.value.value[i]
  wire[wire.len-2] = 128
  wire[wire.len-1] = 0
  let before = getOccupiedMem()
  assert decodeActivityState(wire, policy()).error == ActivityError.NonCanonical
  assert before == getOccupiedMem()
  var duplicate = source(43)
  duplicate.services[1].service = ServiceIndex(255)
  assert activityStateEntry(duplicate, policy()).error == ActivityError.NonCanonical
  var emptySource = source(0)
  emptySource.services = @[]
  let emptyEntry = activityStateEntry(emptySource, policy())
  assert emptyEntry.error == ActivityError.None
  let empty = decodeActivityState(emptyEntry.value.value, policy()).value.snapshot
  assert activityInfo(empty).value.services == 0
  assert serviceActivityAt(empty, StatisticsServiceIndex(0)).error == ActivityError.InvalidIndex

# Trusted nonnegative increments and typed-storage counts still need explicit guards under wrapping arithmetic.
var huge = policy()
huge.maxBytes = ByteLimit(high(uint64))
huge.maxServices = ElementLimit(high(uint64))
var cursor = high(int)-24
assert grow(cursor, 24, huge) == ActivityError.None
assert cursor == high(int)
assert grow(cursor, 1, huge) == ActivityError.LengthOverflow
assert cursor == high(int)
assert grow(cursor, 0, huge) == ActivityError.None
cursor = high(int)-3
assert grow(cursor, 4, huge) == ActivityError.LengthOverflow
assert cursor == high(int)-3
assert serviceCount(uint64(high(int) div sizeof(ServiceStatisticsEntry)), huge) ==
    ActivityError.None
assert serviceCount(uint64(high(int) div sizeof(ServiceStatisticsEntry))+1, huge) ==
    ActivityError.LengthOverflow
assert serviceCount(high(uint64), huge) == ActivityError.LengthOverflow
var strict = huge
strict.maxServices = ElementLimit(0)
assert serviceCount(high(uint64), strict) == ActivityError.LimitExceeded
# Warm up allocator bookkeeping before the isolated scoped occupancy comparison.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Each scope releases the final owner references and all source/copy/failure arrays.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_statistics_private", 1000, beforeRelease, afterRelease)
echo "STATISTICS_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony chapter 13: resized epochs, retained/replaced families, copied values and scoped ARC release passed"
