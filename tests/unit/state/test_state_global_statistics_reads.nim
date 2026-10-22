# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact authenticated activity reads preserve independent epoch populations and accepted compact gas.
import std/[assertions, syncio]
import ../../support/proof_global_helpers
import ../../../src/state/[proof_global, proof_view]
import ../../../src/codec/[bounded, state_statistics, state_layout, state_safrole, state_trie]
let config = ActivityConfig(cores: CoreCount(3), current: ValidatorCount(6),
    previous: ValidatorCount(9),
  maxServices: ElementLimit(1), maxBytes: ByteLimit(4096))
var source = default(ActivityState)
source.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](6)
source.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](9)
source.validators[StatisticsEpoch.Current][0][ValidatorMeasure.Blocks] = ValidatorCounter(high(uint32))
source.validators[StatisticsEpoch.Previous][8][ValidatorMeasure.Assurances] = ValidatorCounter(128)
source.cores = newSeq[CoreActivity](3)
source.cores[2].gas = ActivityGas(high(uint64))
source.services = @[ServiceStatisticsEntry(service: ServiceIndex(high(uint32)), statistics:
  ServiceActivity(refinementGas: ActivityGas(128), accumulationGas: ActivityGas(256)))]
let entry = activityStateEntry(source, config).value
let view = globalView(@[entry], [entry.key])
let owner = view.readGlobalStatistics(config).value
assert owner.activityInfo.value.validators[StatisticsEpoch.Current] == 6
assert owner.activityInfo.value.validators[StatisticsEpoch.Previous] == 9
assert uint32(owner.validatorActivityAt(StatisticsEpoch.Current, StatisticsValidatorIndex(0)).value[
    ValidatorMeasure.Blocks]) == high(uint32)
assert uint32(owner.validatorActivityAt(StatisticsEpoch.Previous, StatisticsValidatorIndex(
    8)).value[ValidatorMeasure.Assurances]) == 128
assert uint64(owner.coreActivityAt(StatisticsCoreIndex(2)).value.gas) == high(uint64)
source = default(ActivityState)
let service = owner.serviceActivityAt(StatisticsServiceIndex(0)).value
assert uint64(service.service) == uint64(high(uint32)) and uint64(
    service.statistics.refinementGas) == 128 and uint64(service.statistics.accumulationGas) == 256
assert default(ProofView).readGlobalStatistics(config).error == GlobalProofError.Uninitialized
assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalStatistics(config).error ==
    GlobalProofError.MissingWitness
assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalStatistics(config).error ==
    GlobalProofError.AbsentValue
var policy = config
policy.maxServices = ElementLimit(0)
assert view.readGlobalStatistics(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.maxBytes = ByteLimit(entry.value.len-1)
assert view.readGlobalStatistics(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.previous = ValidatorCount(0)
assert view.readGlobalStatistics(policy).error == GlobalProofError.InvalidConfig
for length in [0, 1, 145, 362, entry.value.len-1]:
  # Probe current/previous roster, core statistics and final compact-gas boundaries.
  var truncated = newSeq[byte](length)
  for i in 0..<length: truncated[i] = entry.value[i]
  assert globalView(@[StateEntry(key: entry.key, value: truncated)], [
      entry.key]).readGlobalStatistics(config).error == GlobalProofError.InvalidValue
var suffix = entry.value
suffix.add(0)
assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalStatistics(
    config).error == GlobalProofError.InvalidValue
echo "state-global-statistics-reads: ok"
