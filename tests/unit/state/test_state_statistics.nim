# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Supplementary immutable lifetime, copied tuple, independent population and result/index
## guards.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/syncio
import ../../../src/codec/state_statistics as codec_state_statistics
import ../../../src/codec/bounded as codec_bounded

## The retained snapshot outlives local source/wire arrays and preserves all statistical families.
proc captured(config: ActivityConfig): ActivitySnapshot =
  var source = default(ActivityState)
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
  assert encoded.error == ActivityError.None and array[31, byte](encoded.value.key)[0] == 13
  source.validators[StatisticsEpoch.Current][0] = default(ValidatorActivity)
  source.cores[2] = default(CoreActivity)
  source.services[0] = default(ServiceStatisticsEntry)
  assert encoded.value.value[1] == 255
  var wire = encoded.value.value
  let parsed = decodeActivityState(wire, config)
  assert parsed.error == ActivityError.None and parsed.value.consumed == wire.len
  result = parsed.value.snapshot
  for i in 0..<wire.len: wire[i] = 0 # Retained copies must survive caller-wire destruction.
  source = default(ActivityState)

## Known compact gas bytes enforce the maintainer-selected vector representation at all three gas positions.
proc compactGas() =
  var source = default(ActivityState)
  source.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](6)
  source.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](6)
  source.cores = newSeq[CoreActivity](2)
  source.cores[0].gas = ActivityGas(100000)
  source.services = @[ServiceStatisticsEntry(service: ServiceIndex(127), statistics:
    ServiceActivity(refinementGas: ActivityGas(128), accumulationGas: ActivityGas(256)))]
  let config = ActivityConfig(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), maxServices: ElementLimit(1), maxBytes: ByteLimit(326))
  let encoded = activityStateEntry(source, config)
  assert encoded.error == ActivityError.None and encoded.value.value.len == 326
  let wire = encoded.value.value
  assert wire[297] == 0xc1 and wire[298] == 0xa0 and wire[299] == 0x86
  assert wire[316] == 0x80 and wire[317] == 0x80
  assert wire[324] == 0x81 and wire[325] == 0
  let decoded = decodeActivityState(wire, config)
  assert decoded.error == ActivityError.None and decoded.value.consumed == 326
  assert uint64(coreActivityAt(decoded.value.snapshot, StatisticsCoreIndex(0)).value.gas) == 100000
  let service = serviceActivityAt(decoded.value.snapshot, StatisticsServiceIndex(0)).value
  assert uint64(service.statistics.refinementGas) == 128 and uint64(
      service.statistics.accumulationGas) == 256

## Every accessor returns copied fixed values with independent epoch/core/service index domains.
proc main() =
  compactGas() # Byte-level policy is checked alongside lifetime and result guards.
  assert sizeof(int) == 8 and sizeof(ServiceStatisticsEntry) == 96
  let config = ActivityConfig(cores: CoreCount(3), current: ValidatorCount(6),
      previous: ValidatorCount(9),
    maxServices: ElementLimit(1), maxBytes: ByteLimit(1000))
  let owner = captured(config)
  let info = activityInfo(owner).value
  assert info.validators[StatisticsEpoch.Current] == 6 and info.validators[
      StatisticsEpoch.Previous] == 9
  assert info.cores == 3 and info.services == 1
  var validator = validatorActivityAt(owner, StatisticsEpoch.Current, StatisticsValidatorIndex(0)).value
  assert uint32(validator[ValidatorMeasure.Blocks]) == high(uint32)
  validator[ValidatorMeasure.Blocks] = ValidatorCounter(0)
  assert uint32(validatorActivityAt(owner, StatisticsEpoch.Current, StatisticsValidatorIndex(
      0)).value[ValidatorMeasure.Blocks]) == high(uint32)
  assert uint32(validatorActivityAt(owner, StatisticsEpoch.Previous, StatisticsValidatorIndex(
      8)).value[ValidatorMeasure.Assurances]) == 128
  var core = coreActivityAt(owner, StatisticsCoreIndex(2)).value
  assert uint64(core.gas) == high(uint64) and uint64(core.counters[CoreMeasure.BundleBytes]) == 256
  core.gas = ActivityGas(0)
  assert uint64(coreActivityAt(owner, StatisticsCoreIndex(2)).value.gas) == high(uint64)
  var service = serviceActivityAt(owner, StatisticsServiceIndex(0)).value
  assert uint32(service.service) == high(uint32) and uint64(service.statistics.refinementGas) == 256
  assert uint64(service.statistics.accumulationGas) == high(uint64)
  assert uint64(service.statistics.counters[ServiceMeasure.TransferCount]) == 128
  service.statistics = default(ServiceActivity)
  assert uint64(serviceActivityAt(owner, StatisticsServiceIndex(0)).value.statistics.counters[
      ServiceMeasure.ProvisionBytes]) == 127
  var replaced = owner
  replaced = default(ActivitySnapshot)
  assert activityInfo(owner).value.services == 1
  let index = validatorActivityAt(owner, StatisticsEpoch.Current, StatisticsValidatorIndex(8))
  assert index.error == ActivityError.InvalidIndex
  let coreIndex = coreActivityAt(owner, StatisticsCoreIndex(high(uint64)))
  assert coreIndex.error == ActivityError.InvalidIndex
  let serviceIndex = serviceActivityAt(owner, StatisticsServiceIndex(1))
  assert serviceIndex.error == ActivityError.InvalidIndex
  let late = decodeActivityState(@[], config)
  assert late.error == ActivityError.Truncated
  echo "PASS activity: retained tuples, resized epochs, independent copies and result/index guards"

main()
