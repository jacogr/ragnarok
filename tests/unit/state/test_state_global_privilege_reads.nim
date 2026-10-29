# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated role/assigner/always-accumulate fields preserve full-width services and gas values.
import std/[assertions, syncio]
import ../../support/proof_global_helpers
import ../../../src/state/proof/[global as proof_global, view as proof_view]
import ../../../src/codec/bounded
import ../../../src/codec/state/[privileges as state_privileges, layout as state_layout,
    safrole as state_safrole, trie as state_trie]
let config = PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(2), maxBytes: ByteLimit(128))
var source = PrivilegeState(manager: ServiceIndex(high(uint32)), delegator: ServiceIndex(255),
  registrar: ServiceIndex(256), assigners: @[ServiceIndex(7), ServiceIndex(8)],
  always: @[AlwaysAccumulate(service: ServiceIndex(9), gas: PrivilegeGas(high(uint64)))])
let entry = privilegeStateEntry(source, config).value
let view = globalView(@[entry], [entry.key])
let owner = view.readGlobalPrivileges(config).value
assert uint64(owner.privilegeInfo.value.manager) == uint64(high(uint32))
assert uint64(owner.privilegeInfo.value.delegator) == 255 and uint64(
    owner.privilegeInfo.value.registrar) == 256
assert uint64(owner.privilegeAssignerAt(PrivilegeCoreIndex(1)).value) == 8
assert uint64(owner.alwaysAccumulateAt(PrivilegeEntryIndex(0)).value.gas) == high(uint64)
source = default(PrivilegeState)
assert uint64(owner.alwaysAccumulateAt(PrivilegeEntryIndex(0)).value.service) == 9
assert default(ProofView).readGlobalPrivileges(config).error == GlobalProofError.Uninitialized
assert globalView(@[entry], [timeEntry(StateTime(1)).key]).readGlobalPrivileges(config).error ==
    GlobalProofError.MissingWitness
assert globalView(@[timeEntry(StateTime(1))], [entry.key]).readGlobalPrivileges(config).error ==
    GlobalProofError.AbsentValue
var policy = config
policy.maxAlways = ElementLimit(0)
assert view.readGlobalPrivileges(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.maxBytes = ByteLimit(entry.value.len-1)
assert view.readGlobalPrivileges(policy).error == GlobalProofError.LimitExceeded
policy = config
policy.cores = CoreCount(0)
assert view.readGlobalPrivileges(policy).error == GlobalProofError.InvalidConfig
for length in 0..<entry.value.len:
  # Exact role, assigner and dictionary framing is required after membership verification.
  var truncated = newSeq[byte](length)
  for i in 0..<length: truncated[i] = entry.value[i]
  assert globalView(@[StateEntry(key: entry.key, value: truncated)], [
      entry.key]).readGlobalPrivileges(config).error == GlobalProofError.InvalidValue
var suffix = entry.value
suffix.add(0)
assert globalView(@[StateEntry(key: entry.key, value: suffix)], [entry.key]).readGlobalPrivileges(
    config).error == GlobalProofError.InvalidValue
echo "state-global-privilege-reads: ok"
