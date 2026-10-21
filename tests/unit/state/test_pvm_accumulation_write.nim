# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_write_arc_release"}

## Authored writes exercise gas, memory, deposit accounting and immutable implication rollback.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_accounts, state_layout, state_service_values,
    state_trie, c2_records, state_outputs]
import ../../../src/state/[accumulation_dispatch, accumulation_machine, accumulation_invocation,
  accumulation_service, accumulation_context, accumulation_effects, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

## Fault only after authentic source preparation, preserving observer counter ordering.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Permit namespace derivation, then refuse the private candidate Merklization.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
## Count exact backend work before a refusal.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Independent little-endian parameter bytes choose a small deposit schedule without replacing validation.
proc schedule(base = 10'u64, item = 2'u64, octet = 1'u64): Parameters =
  var wire = encodeParameters(pvmParameters())
  for field, amount in [item, octet, base]:
    for i in 0..<8:
      wire[field*8+i] = byte((amount shr (8*i)) and 255) # Three E8 fields precede unrelated chain settings.
  decodeParameters(wire).value

## A single raw storage key has three old bytes and contributes exactly 38 footprint octets.
proc entries(): seq[StateEntry] =
  @[serviceStorageEntry(ServiceIndex(42), @[73'u8], @[3'u8, 4, 5],
    ServiceEntryLimits(keyBytes: ByteLimit(1), valueBytes: ByteLimit(3))).value]

## Build real guest instructions; optional suffixes witness state visibility and terminal normalization.
proc source(keyAddress = 65536'u64, keyLength = 1'u64, valueAddress = 196608'u64,
    valueLength = 3'u64, credit = 100000'u64, existing = false, balance = 10000'u64,
    gratis = 0'u64, spare = 1, suffix: seq[seq[byte]] = @[@[50'u8,
        0]]): PreparedAccumulationMachine =
  var code = @[registerImmediate(7, keyAddress), registerImmediate(8, keyLength),
    registerImmediate(9, valueAddress), registerImmediate(10, valueLength), @[10'u8, 5]]
  for instruction in suffix:
    code.add(instruction) # Every authored instruction retains its real opcode boundary.
  guestProgram(code, credit, extra = (if existing: entries() else: @[]),
    account = ServiceMetadata(balance: AccountBalance(balance), depositOffset: AccountBalance(
        gratis),
      storageItems: AccountStorageItems(if existing: 1'u32 else: 0'u32),
      storageBytes: AccountStorageBytes(if existing: 38'u64 else: 0'u64)), spareEntries = spare)

## Execute through the actual dispatcher; local copy and machine budgets are independent of protocol gas.
proc run(prepared: PreparedAccumulationMachine, limit = 64'u64,
    parameters: Parameters = schedule()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, parameters,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig())

## Actual prepaid block cost is independent of frozen host-price witnesses.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
    GasCycleLimit(1000)).value)

## Retain the selected version's current map, never its historical initial map.
proc accounts(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): StateStoreSnapshot =
  done.effects.effectContext(dimension).value.effectAccounts.value

## Decode complete metadata for independent footprint and unchanged-field assertions.
proc metadata(state: StateStoreSnapshot): ServiceMetadata =
  decodeServiceMetadata(state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      42))).value.bytes,
    ByteLimit(ServiceMetadataBytes)).value.metadata

## Find the exact one-byte raw key from the maintained namespace constructor.
proc stored(state: StateStoreSnapshot): StateStoreResult[StateValue] =
  state.lookup(serviceStorageKey(ServiceIndex(42), @[73'u8], ByteLimit(1)).value)

let regular = AccumulationDimension.Regular
let exceptional = AccumulationDimension.Exceptional
for existing in [false, true]:
  for length in [0'u64, 1, 3, 32]:
    # Insertion/replacement/deletion report prior length, update both counters and preserve all source owners.
    let prepared = source(existing = existing, valueLength = length)
    let done = run(prepared)
    assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
    assert uint64(machineInfo(done.value.machine).value.registers[7]) ==
      (if existing: 3'u64 else: high(uint64))
    let current = accounts(done)
    let facts = metadata(current)
    assert uint32(facts.storageItems) == (if length == 0: 0'u32 else: 1'u32)
    assert uint64(facts.storageBytes) == (if length == 0: 0'u64 else: 35+length)
    assert uint64(facts.balance) == 10000 and uint64(facts.depositOffset) == 0
    let original = prepared.machineBootstrap.value.bootstrapService.value.serviceState.value
    let before = metadata(original)
    assert array[32, byte](before.codeHash) == array[32, byte](facts.codeHash)
    assert uint64(before.minimumAccumulationGas) == uint64(facts.minimumAccumulationGas)
    assert uint64(before.minimumTransferGas) == uint64(facts.minimumTransferGas)
    assert uint32(before.created) == uint32(facts.created) and uint32(before.lastAccumulation) ==
        uint32(facts.lastAccumulation)
    assert uint32(before.parent) == uint32(facts.parent)
    if length == 0:
      assert stored(current).error == StateStoreError.MissingKey # Empty value means deletion, never present-empty storage.
    else:
      let expected = readBytes(memoryOf(prepared.accumulationMachine.value).value, MemoryAddress(
          196608),
        MemoryLength(length), MemoryByteLimit(length)).value
      assert stored(current).value.bytes == expected # Exact bytes are captured from readable guest memory.
    assert array[32, byte](accounts(done, exceptional).commitment.root) == array[32, byte](
        original.commitment.root)
    assert uint32(metadata(original).storageItems) == (if existing: 1'u32 else: 0'u32)
    assert uint64(machineInfo(prepared.accumulationMachine.value).value.gas) == 100000
# Deposit threshold for one key byte and three value bytes is 10+2+38=50; equality is accepted.
for witness in [(49'u64, 0'u64, false), (50'u64, 0'u64, true), (0'u64, 50'u64, true),
    (25'u64, 24'u64, false), (25'u64, 25'u64, true)]:
  let (balance, gratis, accepted) = witness
  let prepared = source(balance = balance, gratis = gratis)
  let done = run(prepared)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
  assert uint64(machineInfo(done.value.machine).value.registers[7]) ==
    (if accepted: high(uint64) else: high(uint64)-4)
  assert uint32(metadata(accounts(done)).storageItems) == (if accepted: 1'u32 else: 0'u32)
# Even deletion is FULL if the candidate remains below base deposit; its old bytes survive.
let underfundedDelete = run(source(existing = true, valueLength = 0, balance = 9))
assert uint64(machineInfo(underfundedDelete.value.machine).value.registers[7]) == high(uint64)-4
assert stored(accounts(underfundedDelete)).value.bytes == @[3'u8, 4, 5]
let wideBudget = run(source(balance = high(uint64), gratis = high(uint64)),
  parameters = schedule(base = high(uint64), item = high(uint64), octet = 0))
assert uint64(machineInfo(wideBudget.value.machine).value.registers[7]) == high(uint64)
let wideFull = run(source(balance = high(uint64), gratis = high(uint64)),
    parameters = pvmParameters())
assert uint64(machineInfo(wideFull.value.machine).value.registers[7]) == high(uint64)-4
# Zero value length never touches an invalid value pointer; an empty raw key accepts any input pointer.
assert run(source(valueAddress = high(uint64), valueLength = 0)).value.exit == StepExit.Halt
let emptyKey = run(source(keyAddress = high(uint64), keyLength = 0))
assert emptyKey.error == AccumulationDispatchError.None and emptyKey.value.exit == StepExit.Halt
for address in [0'u64, 196608'u64+8192-1, 0x100000000'u64, high(uint64)]:
  let failed = run(source(valueAddress = address))
  assert failed.value.exit == StepExit.Panic # Bad value range cannot change either implication map.
  assert uint32(metadata(accounts(failed)).storageItems) == 0
for address in [0'u64, 0x100010000'u64, high(uint64)]:
  let failed = run(source(keyAddress = address))
  assert failed.value.exit == StepExit.Panic and uint64(machineInfo(
      failed.value.machine).value.registers[7]) == address
assert run(source(keyLength = 65), limit = 64).error == AccumulationDispatchError.LimitExceeded
assert run(source(valueLength = 65), limit = 64).error == AccumulationDispatchError.LimitExceeded
assert run(source(spare = 0)).error == AccumulationDispatchError.LimitExceeded
let valid = source()
failHash(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure and hashCalls() == 1
failHash(0)
failAfter(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure and hashCalls() == 2
failHash(0)
# Read-only and crossing-page value ranges are valid inputs; overlapping key/value capture stays independent.
for address in [65536'u64, 196608'u64+4096-1]:
  assert run(source(valueAddress = address)).value.exit == StepExit.Halt
let overlapping = run(source(valueAddress = 65536, valueLength = 1))
assert stored(accounts(overlapping)).value.bytes == @[73'u8]
# Read sees the new current account, including exact metadata/storage linkage.
let readback = run(source(suffix = @[registerImmediate(7, high(uint64)), registerImmediate(8, 65536),
  registerImmediate(9, 1), registerImmediate(10, 196736), registerImmediate(11, 0),
  registerImmediate(12, 3), @[10'u8, 4], @[50'u8, 0]]))
assert readback.error == AccumulationDispatchError.None and readback.value.exit == StepExit.Halt
assert uint64(machineInfo(readback.value.machine).value.registers[7]) == 3
assert readBytes(memoryOf(readback.value.machine).value, MemoryAddress(196736), MemoryLength(3),
  MemoryByteLimit(3)).value == @[81'u8, 0, 0]
for checkpoint in [false, true]:
  # Panic selects the retained checkpoint; prior initial provenance always stays unchanged.
  let ending = (if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])
  let done = run(source(suffix = ending))
  assert done.value.exit == StepExit.Panic
  let normalized = normalizeAccumulationOutcome(done)
  assert normalized.error == AccumulationOutcomeError.None
  let selected = normalized.value.outcomeContext.value.effectAccounts.value
  assert uint32(metadata(selected).storageItems) == (if checkpoint: 1'u32 else: 0'u32)
for checkpoint in [false, true]:
  # A later host OOG follows the same checkpoint selection as panic, after a completed write.
  let suffix = (if checkpoint: @[@[10'u8, 19], @[10'u8, 0], @[50'u8, 0]]
    else: @[@[10'u8, 0], @[50'u8, 0]])
  let prototype = source(suffix = suffix)
  let prepared = source(suffix = suffix, credit = price(prototype)+2447+10+(
      if checkpoint: 103'u64 else: 0'u64))
  let done = run(prepared)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.OutOfGas
  let selected = normalizeAccumulationOutcome(done).value.outcomeContext.value.effectAccounts.value
  assert uint32(metadata(selected).storageItems) == (if checkpoint: 1'u32 else: 0'u32)
# Frozen independently calculated prices cover separate rounding and every affordability edge.
for witness in [(0'u64, 0'u64, 2442'u64), (1'u64, 1'u64, 2447'u64),
    (1023'u64, 1023'u64, 6013'u64), (1024'u64, 1024'u64, 6016'u64),
    (1025'u64, 1025'u64, 6021'u64)]:
  let (keyLength, valueLength, cost) = witness
  let prototype = source(keyLength = keyLength, valueLength = valueLength)
  for available in [0'u64, cost-1]:
    let done = run(source(keyLength = keyLength, valueLength = valueLength,
      keyAddress = high(uint64), credit = price(prototype)+available), limit = 0)
    assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.OutOfGas
    assert uint64(machineInfo(done.value.machine).value.gasDeficit) == 0
for available in [2447'u64, 2448'u64]:
  let prototype = source(valueLength = 1)
  let done = run(source(valueLength = 1, credit = price(prototype)+available))
  assert done.value.exit == StepExit.Halt and uint64(machineInfo(done.value.machine).value.gas) == available-2447
assert run(source(keyLength = high(uint64), valueLength = high(uint64)), limit = 0).value.exit ==
    StepExit.OutOfGas
# Full-width value pricing and key-cost carry preserve exact representable debt.
let largePrototype = source(keyLength = 5764607523034234880'u64, valueLength = high(uint64))
let large = run(source(keyLength = 5764607523034234880'u64, valueLength = high(uint64),
    credit = high(uint64)), limit = 0)
assert large.error == AccumulationDispatchError.None and large.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(large.value.machine).value.gasDeficit) == 0
let boundaryPrototype = source(keyLength = 3458764513820540928'u64,
    valueLength = 1152921504606846976'u64)
let boundaryCredit = 2362138004555827594'u64+price(boundaryPrototype)
let boundary = run(source(keyLength = 3458764513820540928'u64,
    valueLength = 1152921504606846976'u64, credit = boundaryCredit), limit = 0)
assert boundary.error == AccumulationDispatchError.None and boundary.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(boundary.value.machine).value.gasDeficit) == 0
assert run(source(keyLength = 3458764513820540928'u64, valueLength = 1152921504606846976'u64,
    credit = boundaryCredit-1), limit = 0).value.exit == StepExit.OutOfGas
## Prepare authentic effects for direct immutable API and malformed-footprint witnesses.
proc initial(account: ServiceMetadata, extra: seq[StateEntry] = @[]): AccumulationEffects =
  let prepared = guestProgram([@[50'u8, 0]], account = account, extra = extra, spareEntries = 1)
  prepareAccumulationEffects(prepareAccumulationContexts(prepared.machineBootstrap.value,
    pvmContextConfig()).value).value

let baseEffects = initial(ServiceMetadata(balance: AccountBalance(10000)))
let first = recordAccumulationStorage(baseEffects, @[73'u8], @[1'u8, 2, 3], schedule(), ByteLimit(3))
assert first.error == AccumulationEffectError.None and not first.value.hadValue
let checked = checkpointAccumulationEffects(first.value.effects).value
let yielded = recordAccumulationYield(checked, default(OutputCommitment)).value
let second = recordAccumulationStorage(yielded, @[73'u8], @[4'u8], schedule(), ByteLimit(3))
assert second.error == AccumulationEffectError.None and second.value.hadValue and
    second.value.previousBytes == 3
let current = second.value.effects.effectContext(regular).value
let checkpointed = second.value.effects.effectContext(exceptional).value
assert stored(current.effectAccounts.value).value.bytes == @[4'u8]
assert stored(checkpointed.effectAccounts.value).value.bytes == @[1'u8, 2, 3]
assert current.effectInfo.value.hasYield and not checkpointed.effectInfo.value.hasYield
assert stored(baseEffects.effectContext(regular).value.effectAccounts.value).error ==
    StateStoreError.MissingKey
assert stored(current.effectInitialContext.value.contextAccounts.value).error ==
    StateStoreError.MissingKey
for metadata in [ServiceMetadata(balance: AccountBalance(10000), storageItems: AccountStorageItems(
    0), storageBytes: AccountStorageBytes(38)), ServiceMetadata(balance: AccountBalance(10000),
    storageItems: AccountStorageItems(1), storageBytes: AccountStorageBytes(37))]:
  let corrupt = initial(metadata, entries())
  assert recordAccumulationStorage(corrupt, @[73'u8], @[], schedule(), ByteLimit(3)).error ==
    AccumulationEffectError.MalformedState # Existing footprint cannot underflow either counter.
let emptyStored = initial(ServiceMetadata(balance: AccountBalance(10000),
    storageItems: AccountStorageItems(1),
  storageBytes: AccountStorageBytes(35)), @[serviceStorageEntry(ServiceIndex(42), @[73'u8], @[],
  ServiceEntryLimits(keyBytes: ByteLimit(1), valueBytes: ByteLimit(0))).value])
let removedEmpty = recordAccumulationStorage(emptyStored, @[73'u8], @[], schedule(), ByteLimit(1))
assert removedEmpty.error == AccumulationEffectError.None and removedEmpty.value.hadValue and
    removedEmpty.value.previousBytes == 0
assert uint32(metadata(removedEmpty.value.effects.effectContext(
    regular).value.effectAccounts.value).storageItems) == 0
let fullItems = initial(ServiceMetadata(balance: AccountBalance(high(uint64)),
  storageItems: AccountStorageItems(high(uint32))))
assert recordAccumulationStorage(fullItems, @[73'u8], @[1'u8], schedule(0, 0, 0), ByteLimit(
    1)).error ==
  AccumulationEffectError.InvalidState
let fullBytes = initial(ServiceMetadata(balance: AccountBalance(high(uint64)),
  storageBytes: AccountStorageBytes(high(uint64))))
assert recordAccumulationStorage(fullBytes, @[73'u8], @[1'u8], schedule(0, 0, 0), ByteLimit(
    1)).error ==
  AccumulationEffectError.InvalidState
assert recordAccumulationStorage(default(AccumulationEffects), @[], @[], schedule(), ByteLimit(
    0)).error ==
  AccumulationEffectError.Uninitialized
assert recordAccumulationStorage(baseEffects, @[], @[], default(Parameters), ByteLimit(0)).error ==
  AccumulationEffectError.InvalidParameters
assert recordAccumulationStorage(baseEffects, @[1'u8], @[], schedule(), ByteLimit(0)).error ==
  AccumulationEffectError.LimitExceeded
let before = getOccupiedMem()
for iteration in 0..<1000:
  let done = run(valid)
  assert stored(accounts(done)).value.bytes == @[81'u8, 0,
      0] # Every execution releases all private candidate maps.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_write", 1000, before, after)
echo "PVM accumulation write passed"
echo "ARC_RELEASE cycles=1000 unchanged"
