## Supplementary immutable lifetime, copied tuple, independent population and result/index guards.
import ../../src/[state_statistics, bounded]

## Failed/default alternatives must retain active runtime protection against success-payload access.
proc guarded[T](parsed: ActivityResult[T]) =
  var caught = false
  try:
    discard parsed.value # Default and failures cannot expose initialized application state.
  except FieldDefect:
    caught = true # Field checks remain enabled in optimized LTO builds.
  doAssert caught

## The retained snapshot outlives local source/wire arrays and preserves all statistical families.
proc captured(config: ActivityConfig): ActivitySnapshot =
  var source: ActivityState
  source.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](6)
  source.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](9)
  source.cores = newSeq[CoreActivity](3)
  source.validators[StatisticsEpoch.Current][0][ValidatorMeasure.Blocks] = ValidatorCounter(high(uint32))
  source.validators[StatisticsEpoch.Previous][8][ValidatorMeasure.Assurances] = ValidatorCounter(128)
  source.cores[2].counters[CoreMeasure.BundleBytes] = ActivityNatural(256)
  source.cores[2].gas = ActivityGas(high(uint64))
  var record = ServiceStatisticsEntry(service: ServiceIndex(high(uint32)))
  record.statistics.counters[ServiceMeasure.ProvisionBytes] = ActivityNatural(127)
  record.statistics.counters[ServiceMeasure.TransferCount] = ActivityNatural(128)
  record.statistics.refinementGas = ActivityGas(256)
  record.statistics.accumulationGas = ActivityGas(high(uint64))
  source.services = @[record]
  let encoded = activityStateEntry(source, config)
  doAssert encoded.error == ActivityError.None and array[31, byte](encoded.value.key)[0] == 13
  source.validators[StatisticsEpoch.Current][0] = default(ValidatorActivity)
  source.cores[2] = default(CoreActivity)
  source.services[0] = default(ServiceStatisticsEntry)
  doAssert encoded.value.value[1] == 255
  var wire = encoded.value.value
  let parsed = decodeActivityState(wire, config)
  doAssert parsed.error == ActivityError.None and parsed.value.consumed == wire.len
  result = parsed.value.snapshot
  for i in 0..<wire.len: wire[i] = 0 # Retained copies must survive caller-wire destruction.
  source = default(ActivityState)

## Every accessor returns copied fixed values with independent epoch/core/service index domains.
proc main() =
  doAssert sizeof(int) == 8 and sizeof(ServiceStatisticsEntry) == 96
  let config = ActivityConfig(cores: CoreCount(3), current: ValidatorCount(6),
      previous: ValidatorCount(9),
    maxServices: ElementLimit(1), maxBytes: ByteLimit(1000))
  let owner = captured(config)
  let info = activityInfo(owner).value
  doAssert info.validators[StatisticsEpoch.Current] == 6 and info.validators[
      StatisticsEpoch.Previous] == 9
  doAssert info.cores == 3 and info.services == 1
  var validator = validatorActivityAt(owner, StatisticsEpoch.Current, StatisticsValidatorIndex(0)).value
  doAssert uint32(validator[ValidatorMeasure.Blocks]) == high(uint32)
  validator[ValidatorMeasure.Blocks] = ValidatorCounter(0)
  doAssert uint32(validatorActivityAt(owner, StatisticsEpoch.Current, StatisticsValidatorIndex(
      0)).value[ValidatorMeasure.Blocks]) == high(uint32)
  doAssert uint32(validatorActivityAt(owner, StatisticsEpoch.Previous, StatisticsValidatorIndex(
      8)).value[ValidatorMeasure.Assurances]) == 128
  var core = coreActivityAt(owner, StatisticsCoreIndex(2)).value
  doAssert uint64(core.gas) == high(uint64) and uint64(core.counters[CoreMeasure.BundleBytes]) == 256
  core.gas = ActivityGas(0)
  doAssert uint64(coreActivityAt(owner, StatisticsCoreIndex(2)).value.gas) == high(uint64)
  var service = serviceActivityAt(owner, StatisticsServiceIndex(0)).value
  doAssert uint32(service.service) == high(uint32) and uint64(service.statistics.refinementGas) == 256
  doAssert uint64(service.statistics.accumulationGas) == high(uint64)
  doAssert uint64(service.statistics.counters[ServiceMeasure.TransferCount]) == 128
  service.statistics = default(ServiceActivity)
  doAssert uint64(serviceActivityAt(owner, StatisticsServiceIndex(0)).value.statistics.counters[
      ServiceMeasure.ProvisionBytes]) == 127
  var replaced = owner
  replaced = default(ActivitySnapshot)
  guarded(activityInfo(replaced))
  guarded(validatorActivityAt(replaced, StatisticsEpoch.Current, StatisticsValidatorIndex(0)))
  guarded(coreActivityAt(replaced, StatisticsCoreIndex(0)))
  guarded(serviceActivityAt(replaced, StatisticsServiceIndex(0)))
  doAssert activityInfo(owner).value.services == 1
  let index = validatorActivityAt(owner, StatisticsEpoch.Current, StatisticsValidatorIndex(8))
  doAssert index.error == ActivityError.InvalidIndex
  guarded(index)
  let coreIndex = coreActivityAt(owner, StatisticsCoreIndex(high(uint64)))
  doAssert coreIndex.error == ActivityError.InvalidIndex
  guarded(coreIndex)
  let serviceIndex = serviceActivityAt(owner, StatisticsServiceIndex(1))
  doAssert serviceIndex.error == ActivityError.InvalidIndex
  guarded(serviceIndex)
  guarded(default(ActivityResult[ActivityRead]))
  let late = decodeActivityState(@[], config)
  doAssert late.error == ActivityError.Truncated
  guarded(late)
  echo "PASS activity: retained tuples, resized epochs, independent copies and result/index guards"

main()
