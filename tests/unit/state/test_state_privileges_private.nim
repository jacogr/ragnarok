# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only lifetime, numeric-order, copied-value and host-arithmetic tests; no private
## runtime hooks.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import ../../support/arc_evidence
import std/[assertions, syncio]
include ../../../src/codec/state_privileges

## Small explicit per-component work and byte ceilings include every fixed role and dictionary count.
proc policy(): PrivilegeConfig =
  PrivilegeConfig(cores: CoreCount(2), maxAlways: ElementLimit(2), maxBytes: ByteLimit(100))

## Author numeric keys whose little-endian octet order differs, with the full unsigned gas domain.
proc source(marker: uint32): PrivilegeState =
  PrivilegeState(manager: ServiceIndex(marker), delegator: ServiceIndex(128),
      registrar: ServiceIndex(high(uint32)),
    assigners: @[ServiceIndex(marker), ServiceIndex(256)], always: @[
      AlwaysAccumulate(service: ServiceIndex(255), gas: PrivilegeGas(high(uint64))),
      AlwaysAccumulate(service: ServiceIndex(256), gas: PrivilegeGas(0))])

## Retain only the private copied parent after local source, encoded entry and mutable wire retire.
proc escaped(marker: uint32): PrivilegeSnapshot =
  var original = source(marker)
  let entry = privilegeStateEntry(original, policy())
  assert entry.error == PrivilegeError.None
  var wire = entry.value.value
  let parsed = decodePrivilegeState(wire, policy())
  assert parsed.error == PrivilegeError.None
  result = parsed.value.snapshot
  original = default(PrivilegeState)
  # Destroy each caller byte before any observation outside this scope.
  for i in 0..<wire.len: wire[i] = 0

## Each scope retires replaced/retained parents, independent metadata/pairs and late-failure temporaries.
proc cycle() =
  var owner = escaped(17)
  let alias = owner
  owner = escaped(29)
  assert uint32(privilegeInfo(alias).value.manager) == 17
  assert uint32(privilegeAssignerAt(owner, PrivilegeCoreIndex(0)).value) == 29
  var info = privilegeInfo(alias).value
  info.manager = ServiceIndex(0)
  info.cores = 0
  assert uint32(privilegeInfo(alias).value.manager) == 17
  assert privilegeInfo(alias).value.cores == 2
  var pair = alwaysAccumulateAt(alias, PrivilegeEntryIndex(0)).value
  pair.service = ServiceIndex(0)
  pair.gas = PrivilegeGas(0)
  assert uint32(alwaysAccumulateAt(alias, PrivilegeEntryIndex(0)).value.service) == 255
  assert uint64(alwaysAccumulateAt(alias, PrivilegeEntryIndex(0)).value.gas) == high(uint64)
  assert uint32(alwaysAccumulateAt(alias, PrivilegeEntryIndex(1)).value.service) == 256
  owner = default(PrivilegeSnapshot)
  assert privilegeInfo(owner).error == PrivilegeError.InvalidOwner
  assert privilegeInfo(alias).value.always == 2
  assert privilegeAssignerAt(alias, PrivilegeCoreIndex(high(uint64))).error ==
      PrivilegeError.InvalidIndex
  assert alwaysAccumulateAt(alias, PrivilegeEntryIndex(high(uint64))).error ==
      PrivilegeError.InvalidIndex
  var original = source(43)
  var wire = privilegeStateEntry(original, policy()).value.value
  # Two equal numeric service keys reject even when the gas values differ.
  for i in 0..<4:
    let octet = wire[21+i]
    wire[33+i] = octet
  let before = getOccupiedMem()
  assert decodePrivilegeState(wire, policy()).error == PrivilegeError.NonCanonical
  assert before == getOccupiedMem()
  let repeated = original.always[0]
  original.always[1] = repeated
  assert privilegeStateEntry(original, policy()).error == PrivilegeError.NonCanonical
  let emptySource = PrivilegeState(assigners: @[ServiceIndex(0), ServiceIndex(0)])
  let emptyEntry = privilegeStateEntry(emptySource, policy())
  assert emptyEntry.error == PrivilegeError.None and emptyEntry.value.value.len == 21
  let empty = decodePrivilegeState(emptyEntry.value.value, policy()).value.snapshot
  assert privilegeInfo(empty).value.always == 0
  assert alwaysAccumulateAt(empty, PrivilegeEntryIndex(0)).error == PrivilegeError.InvalidIndex

# Direct arithmetic/storage probes never fabricate sequence descriptors or allocate announced extents.
var huge = policy()
huge.maxBytes = ByteLimit(high(uint64))
huge.maxAlways = ElementLimit(high(uint64))
var cursor = high(int)-12
assert grow(cursor, 12, huge) == PrivilegeError.None
assert cursor == high(int)
assert grow(cursor, 1, huge) == PrivilegeError.LengthOverflow
assert cursor == high(int)
assert grow(cursor, 0, huge) == PrivilegeError.None
cursor = high(int)-7
assert grow(cursor, 8, huge) == PrivilegeError.LengthOverflow
assert cursor == high(int)-7
cursor = 0
assert grow(cursor, high(int), huge) == PrivilegeError.None
assert cursor == high(int)
assert countError(uint64(high(int) div sizeof(AlwaysAccumulate)), huge) == PrivilegeError.None
assert countError(uint64(high(int) div sizeof(AlwaysAccumulate))+1, huge) ==
    PrivilegeError.LengthOverflow
assert countError(high(uint64), huge) == PrivilegeError.LengthOverflow
var strict = huge
strict.maxAlways = ElementLimit(0)
assert countError(high(uint64), strict) == PrivilegeError.LimitExceeded
# Warm up allocator bookkeeping before the isolated scoped comparison.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Final ARC references and every source/copy/failure temporary retire at scope exit.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_privileges_private", 1000, beforeRelease, afterRelease)
echo "PRIVILEGES_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony chapter 12: retained/replaced roles, numeric dictionaries, copied fields and scoped ARC release passed"
