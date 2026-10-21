# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_bless_arc_release"}

## Authored bless programs verify exact charging, authority, dictionary capture and checkpoint ownership.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_layout, state_privileges, c2_records]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_machine, accumulation_invocation, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

## Refuse only the first Merklization hash after authentic fixture construction.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Count hashes to distinguish pure authorization/input refusals from attempted publication.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Match the tiny prepared privilege layout while preserving all other validated protocol parameters.
proc parameters(): Parameters =
  var bytes = encodeParameters(pvmParameters())
  for i in 0..<24:
    bytes[i] = 0 # Free deposits isolate role ownership from unrelated storage-funding policy.
  bytes[24] = 2
  bytes[25] = 0 # Core count is the E2 field after the three initial E8 deposit values.
  decodeParameters(bytes).value

## Explicit positive allowance capacity supplements the older empty-dictionary fixture policy.
proc config(): AccumulationContextConfig =
  result = pvmContextConfig()
  result.privileges.maxAlways = ElementLimit(4)

## Explicit E4/E8 test payload construction keeps input record identity independent of the production decoder.
proc payload(pairs: openArray[AlwaysAccumulate]): seq[byte] =
  result = @[]
  for pair in pairs:
    for i in 0..<4:
      result.add(byte((uint32(pair.service) shr (8*i)) and 255)) # Preserve every raw service octet.
    for i in 0..<8:
      result.add(byte((uint64(pair.gas) shr (8*i)) and 255)) # Preserve the complete uint64 gas domain.

## Build authentic host programs with separately controlled current authority and proposed roles.
proc source(manager = 42'u64, assigners = 65536'u64, delegator = 99'u64,
    registrar = uint64(high(uint32)), address = 196608'u64, count = 1'u64,
    initialManager = 42'u32, credit = 100000'u64,
    data: seq[byte] = @[81'u8], suffix: seq[seq[byte]] = @[@[50'u8,
        0]]): PreparedAccumulationMachine =
  var instructions = @[registerImmediate(7, manager), registerImmediate(8, assigners),
    registerImmediate(9, delegator), registerImmediate(10, registrar), registerImmediate(11,
        address),
    registerImmediate(12, count), @[10'u8, 16]]
  for instruction in suffix:
    instructions.add(instruction) # Every host call executes through the real decoded guest stream.
  guestProgram(instructions, credit, manager = initialManager, writable = data, spareEntries = 1)

## Capture and execution policies stay distinct from guest gas; no provision capacity is inferred.
proc run(prepared: PreparedAccumulationMachine, limit = 64'u64,
    params: Parameters = parameters(), profile: AccumulationContextConfig = config()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, params,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), profile)

## Actual instruction pricing is independent of fixed bless-price witnesses.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

## Retain an exact dimension, preserving selected owner lifetimes after local temporaries disappear.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  done.effects.effectContext(dimension).value

## Both public roles and the complete serialized map must describe the same canonical privilege state.
proc checkRoles(context: AccumulationEffectContext, manager: uint32, pairs: seq[AlwaysAccumulate]) =
  let owner = context.effectPrivileges.value
  let info = owner.privilegeInfo.value
  assert uint32(info.manager) == manager and info.cores == 2 and info.always == pairs.len, "uint32(info.manager) == manager and info.cores == 2 and in"
  assert uint32(info.delegator) == 99 and uint32(info.registrar) == high(uint32), "uint32(info.delegator) == 99 and uint32(info.registrar) =="
  assert uint32(owner.privilegeAssignerAt(PrivilegeCoreIndex(0)).value) == 73, "uint32(owner.privilegeAssignerAt(PrivilegeCoreIndex(0)).va"
  assert uint32(owner.privilegeAssignerAt(PrivilegeCoreIndex(1)).value) == 0, "uint32(owner.privilegeAssignerAt(PrivilegeCoreIndex(1)).va"
  let encoded = context.effectAccounts.value.lookup(chapterKey(StateChapter(12))).value.bytes
  let decoded = decodePrivilegeState(encoded, config().privileges).value
  assert decoded.consumed == encoded.len and decoded.snapshot.privilegeInfo.value.always ==
      pairs.len, "decoded.consumed == encoded.len and decoded.snapshot.privi"
  assert uint32(decoded.snapshot.privilegeInfo.value.manager) == manager, "uint32(decoded.snapshot.privilegeInfo.value.manager) == ma"
  for i, pair in pairs:
    let retained = owner.alwaysAccumulateAt(PrivilegeEntryIndex(uint64(i))).value
    let serialized = decoded.snapshot.alwaysAccumulateAt(PrivilegeEntryIndex(uint64(i))).value
    assert uint32(retained.service) == uint32(pair.service) and uint64(retained.gas) == uint64(
        pair.gas), "uint32(retained.service) == uint32(pair.service) and uint6"
    assert uint32(serialized.service) == uint32(pair.service) and uint64(serialized.gas) == uint64(
        pair.gas), "uint32(serialized.service) == uint32(pair.service) and uin"

let singleton = @[AlwaysAccumulate(service: ServiceIndex(81), gas: PrivilegeGas(0))]
let valid = source()
let done = run(valid)
assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt, "done.error == AccumulationDispatchError.None and done.valu"
let cpu = machineInfo(done.value.machine).value
assert uint64(cpu.registers[7]) == 0 and uint64(cpu.gas) == 100000-price(valid)-442, "uint64(cpu.registers[7]) == 0 and uint64(cpu.gas) == 10000"
assert uint64(cpu.registers[8]) == 65536 and uint64(cpu.registers[9]) == 99, "uint64(cpu.registers[8]) == 65536 and uint64(cpu.registers"
assert uint64(cpu.registers[10]) == uint64(high(uint32)) and uint64(cpu.registers[11]) == 196608, "uint64(cpu.registers[10]) == uint64(high(uint32)) and uint"
assert uint64(cpu.registers[12]) == 1, "uint64(cpu.registers[12]) == 1"
checkRoles(context(done), 42, singleton)
assert uint32(context(done, AccumulationDimension.Exceptional).effectPrivileges.value.privilegeInfo.value.manager) ==
    42, "uint32(context(done, AccumulationDimension.Exceptional).ef"
assert context(done, AccumulationDimension.Exceptional).effectPrivileges.value.privilegeInfo.value.always ==
    0, "context(done, AccumulationDimension.Exceptional).effectPri"
assert uint32(context(done).effectInitialContext.value.contextPrivileges.value.privilegeInfo.value.delegator) ==
    0, "uint32(context(done).effectInitialContext.value.contextPri"
# Host input is a set: canonical order is numeric and identical complete pairs collapse.
let unordered = @[AlwaysAccumulate(service: ServiceIndex(high(uint32)), gas: PrivilegeGas(high(uint64))),
  AlwaysAccumulate(service: ServiceIndex(0), gas: PrivilegeGas(17)),
  AlwaysAccumulate(service: ServiceIndex(0), gas: PrivilegeGas(17))]
let canonical = @[unordered[1], unordered[0]]
let sorted = run(source(count = 3, data = payload(unordered)))
assert sorted.error == AccumulationDispatchError.None, "sorted.error == AccumulationDispatchError.None"
checkRoles(context(sorted), 42, canonical)
let empty = run(source(count = 0, address = high(uint64)))
checkRoles(context(empty), 42, @[])
for manager in [0'u64, uint64(high(uint32))]:
  let handed = run(source(manager = manager))
  assert handed.error == AccumulationDispatchError.None, "handed.error == AccumulationDispatchError.None"
  checkRoles(context(handed), uint32(manager), singleton) # No existence check or self sentinel is invented for role IDs.
for index in [7, 9, 10]:
  # Every proposed role is validated at full width only after authorized input capture.
  let proposed = (if index == 7: high(uint64) else: 42'u64)
  let failed = run(source(manager = proposed, delegator = (if index == 9: high(
      uint64) else: 99'u64),
    registrar = (if index == 10: 0x100000000'u64 else: uint64(high(uint32)))))
  assert uint64(machineInfo(failed.value.machine).value.registers[7]) == high(uint64)-3, "uint64(machineInfo(failed.value.machine).value.registers[7"
for initial in [0'u32, high(uint32)]:
  let failed = run(source(initialManager = initial, manager = high(uint64)))
  assert failed.value.exit == StepExit.Halt and uint64(machineInfo(
      failed.value.machine).value.registers[7]) == high(uint64)-8, "failed.value.exit == StepExit.Halt and uint64(machineInfo("
for address in [0'u64, 196608'u64+8192-4, 0x100000000'u64, high(uint64)]:
  let failed = run(source(assigners = address, initialManager = 0))
  assert failed.value.exit == StepExit.Panic, "failed.value.exit == StepExit.Panic # Core-array read prec" # Core-array read precedes even a known unauthorized caller.
  let pairFailed = run(source(address = address, initialManager = 0))
  assert pairFailed.value.exit == StepExit.Panic, "pairFailed.value.exit == StepExit.Panic # Full pair-array " # Full pair-array memory likewise precedes HUH.
assert run(source(), limit = 7).error == AccumulationDispatchError.LimitExceeded, "run(source(), limit = 7).error == AccumulationDispatchErro"
assert run(source(), limit = 11).error == AccumulationDispatchError.LimitExceeded, "run(source(), limit = 11).error == AccumulationDispatchErr"
assert run(source(count = 101)).error == AccumulationDispatchError.LimitExceeded, "run(source(count = 101)).error == AccumulationDispatchErro"
assert run(source(), params = pvmParameters()).error == AccumulationDispatchError.InvalidContext, "run(source(), params = pvmParameters()).error == Accumulat"
# Conflicting service/gas pairs cannot be converted into a dictionary by an arbitrary overwrite rule.
let conflicting = @[AlwaysAccumulate(service: ServiceIndex(1), gas: PrivilegeGas(1)),
  AlwaysAccumulate(service: ServiceIndex(1), gas: PrivilegeGas(2))]
assert run(source(count = 2, data = payload(conflicting))).error ==
    AccumulationDispatchError.AmbiguousPrivileges, "run(source(count = 2, data = payload(conflicting))).error "
for count in [0'u64, 1, 2, 3]:
  let cost = 422+20*count # Independently authored small integer witness, separate from limb arithmetic.
  let prototype = source(count = count)
  for available in [0'u64, cost-1, cost, cost+1]:
    let prepared = source(count = count, credit = price(prototype)+available)
    let completed = run(prepared)
    assert completed.error == AccumulationDispatchError.None, "completed.error == AccumulationDispatchError.None"
    let cpu = machineInfo(completed.value.machine).value
    if available < cost:
      assert completed.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0, "completed.value.exit == StepExit.OutOfGas and uint64(cpu.g"
      assert not normalizeAccumulationOutcome(completed).value.outcomeContext.value.effectInfo.value.hasPrivileges, "unfunded bless has no provenance"
      assert uint64(cpu.registers[7]) == 42, "uint64(cpu.registers[7]) == 42 # No memory capture or stat" # No memory capture or state mutation before affordability.
    else:
      assert completed.value.exit == StepExit.Halt and uint64(cpu.gas) == available-cost, "completed.value.exit == StepExit.Halt and uint64(cpu.gas) "
let hugePrototype = source(count = 0x1000000000000000'u64)
let huge = run(source(count = 0x1000000000000000'u64, credit = high(uint64)), limit = 0)
assert huge.error == AccumulationDispatchError.None and huge.value.exit == StepExit.OutOfGas, "huge.error == AccumulationDispatchError.None and huge.valu"
assert uint64(machineInfo(huge.value.machine).value.gasDeficit) == 0, "uint64(machineInfo(huge.value.machine).value.gasDeficit) ="
let boundaryPrototype = source(count = 0x800000000000000'u64)
let boundaryCredit = 2305843009213694374'u64+price(boundaryPrototype)
let boundary = run(source(count = 0x800000000000000'u64, credit = boundaryCredit), limit = 0)
assert boundary.error == AccumulationDispatchError.None and boundary.value.exit ==
    StepExit.OutOfGas, "exact signed debt"
assert uint64(machineInfo(boundary.value.machine).value.gasDeficit) == 0, "retain 2^63 debt"
assert run(source(count = 0x800000000000000'u64, credit = boundaryCredit-1),
    limit = 0).value.exit == StepExit.OutOfGas, "unrepresentable debt refuses"
assert run(source(count = high(uint64)), limit = 0).value.exit == StepExit.OutOfGas, "run(source(count = high(uint64)), limit = 0).error =="
failHash(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure and hashCalls() == 1, "run(valid).error == AccumulationDispatchError.BackendFailu"
failHash(0)
let unauthorized = source(initialManager = 0)
failHash(1)
assert uint64(machineInfo(run(unauthorized).value.machine).value.registers[7]) == high(uint64)-8, "uint64(machineInfo(run(unauthorized).value.machine).value."
assert hashCalls() == 0, "hashCalls() == 0"
failHash(0)
for checkpoint in [false, true]:
  let suffix = (if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])
  let completed = run(source(suffix = suffix))
  assert completed.value.exit == StepExit.Panic, "completed.value.exit == StepExit.Panic"
  let selected = normalizeAccumulationOutcome(completed).value.outcomeContext.value
  assert selected.effectInfo.value.hasPrivileges == checkpoint, "bless provenance follows terminal checkpoint"
  assert selected.effectPrivileges.value.privilegeInfo.value.always == (if checkpoint: 1 else: 0), "selected.effectPrivileges.value.privilegeInfo.value.always"
# A later unaffordable host call selects exactly the checkpoint's privilege provenance.
for checkpoint in [false, true]:
  var suffix: seq[seq[byte]] = @[]
  if checkpoint:
    suffix.add(@[10'u8, 19]) # Retain the successful bless before the later exhaustion.
  suffix.add(registerImmediate(12, 1000000))
  suffix.add(@[10'u8, 16]) # Full host charge exhausts gas before authority or memory checks.
  suffix.add(@[50'u8, 0]) # The suspended call retains a valid continuation instruction even though gas is exhausted.
  let completed = run(source(suffix = suffix))
  assert completed.error == AccumulationDispatchError.None and completed.value.exit ==
      StepExit.OutOfGas
  let selected = normalizeAccumulationOutcome(completed).value.outcomeContext.value
  assert selected.effectInfo.value.hasPrivileges == checkpoint
# A successful manager handoff makes the original service unauthorized for its next bless call.
let handed = run(source(manager = 99, suffix = @[registerImmediate(7, 42), @[10'u8, 16], @[50'u8, 0]]))
assert uint64(machineInfo(handed.value.machine).value.registers[7]) == high(uint64)-8, "uint64(machineInfo(handed.value.machine).value.registers[7"
checkRoles(context(handed), 99, singleton)
# Later yield and storage mutations must retain the accepted current privilege snapshot and C(12).
let preserved = run(source(suffix = @[registerImmediate(7, 65536), @[10'u8, 27],
  registerImmediate(7, 65536), registerImmediate(8, 1), registerImmediate(9, 196608),
  registerImmediate(10, 3), @[10'u8, 5], @[50'u8, 0]]))
assert preserved.error == AccumulationDispatchError.None and preserved.value.exit == StepExit.Halt, "preserved.error == AccumulationDispatchError.None and pres"
checkRoles(context(preserved), 42, singleton)
assert context(preserved).effectInfo.value.hasPrivileges, "yield and storage retain successful bless provenance"
assert context(preserved).effectInfo.value.hasYield, "context(preserved).effectInfo.value.hasYield"
# The encoded chapter's ceiling is independent of input capture and raw item limits.
var smallProfile = config()
smallProfile.privileges.maxBytes = ByteLimit(32)
assert run(source(), profile = smallProfile).error == AccumulationDispatchError.LimitExceeded, "complete C12 limit"
# API inputs are borrowed only during the call; later caller mutations cannot change accepted snapshots.
let original = empty.effects
var roles = PrivilegeState(manager: ServiceIndex(42), delegator: ServiceIndex(99),
    registrar: ServiceIndex(high(uint32)),
  assigners: @[ServiceIndex(73), ServiceIndex(0)], always: @[AlwaysAccumulate(service: ServiceIndex(
      7), gas: PrivilegeGas(9))])
let recorded = recordAccumulationBless(original, roles, config().privileges)
assert recorded.error == AccumulationEffectError.None, "direct bless success"
roles.assigners[0] = ServiceIndex(1)
roles.always[0].gas = PrivilegeGas(1)
let independent = recorded.value.effectContext(AccumulationDimension.Regular).value
checkRoles(independent, 42, @[AlwaysAccumulate(service: ServiceIndex(7), gas: PrivilegeGas(9))])
assert original.effectContext(AccumulationDimension.Regular).value.effectPrivileges.value.privilegeInfo.value.always ==
    0, "prior owner remains empty"
let defaultContext = default(AccumulationEffectContext)
assert defaultContext.effectPrivileges.error == AccumulationEffectError.Uninitialized, "defaultContext.effectPrivileges.error == AccumulationEffec"
assert recordAccumulationBless(default(AccumulationEffects), default(PrivilegeState),
    config().privileges).error ==
  AccumulationEffectError.Uninitialized, "recordAccumulationBless(default(AccumulationEffects), defa"
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  checkRoles(context(completed), 42, singleton) # Release every private map, role and guest-state successor.
let after = getOccupiedMem()
assert before == after, "before == after"
recordArcRelease("pvm_accumulation_bless", 1000, before, after)
echo "PVM accumulation bless passed"
echo "ARC_RELEASE cycles=1000 unchanged"
