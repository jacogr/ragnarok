# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_eject_arc_release"}

## Current Omega_J guests cover supervisor incarnations, empty juniors, atomic dual-balance reclamation and ARC.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_layout, state_accounts, state_trie, c2_records, header]
import ../../../src/state/[accumulation_dispatch, accumulation_effects, accumulation_context,
  accumulation_machine, accumulation_invocation, accumulation_outcome, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

## Fail actual maintained hashes after fixture preparation, including late private-map failures.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Count backend calls to distinguish metadata checks from publication work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
## Reject a selected complete-map hash without substituting a test implementation.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}

## The invoker has creation slot11; current authorization binds both that slot and service42.
proc junior(balance = 77'u64, supervised = 13'u64, supervisor = 42'u32,
    supervisorCreated = 11'u32, created = 7'u32, items = 0'u32): ServiceMetadata =
  ServiceMetadata(balance: AccountBalance(balance), supervisorBalance: AccountBalance(supervised),
    supervisor: ServiceIndex(supervisor), supervisorCreated: AccountSlot(supervisorCreated),
    created: AccountSlot(created), storageItems: AccountStorageItems(items))

## Register8 is deliberately unreadable: current eject takes only r7 and must not capture the former hash.
proc source(target = 99'u64, targetId = 99'u32, metadata = junior(), selfBalance = 100'u64,
    selfSupervised = 9'u64, slot = 128'u32, credit = 100000'u64, writes = 2'u64,
    includeTarget = true, extra: seq[StateEntry] = @[], suffix: seq[seq[byte]] = @[@[50'u8,
        0]]): PreparedAccumulationMachine =
  var rows = extra
  if includeTarget:
    rows.add(serviceMetadataEntry(ServiceIndex(targetId), metadata,
      ByteLimit(ServiceMetadataBytes)).value) # Preserve the exact caller-authored supervisor incarnation.
  var instructions = @[registerImmediate(7, target), registerImmediate(8, high(uint64)), @[10'u8, 23]]
  for instruction in suffix:
    instructions.add(instruction) # Real later guest instructions observe the same retained implication version.
  guestProgram(instructions, credit, account = ServiceMetadata(balance: AccountBalance(selfBalance),
    supervisorBalance: AccountBalance(selfSupervised), created: AccountSlot(11)),
    extra = rows, writes = writes, slot = HeaderSlot(slot), spareEntries = 2)

## No guest-memory copy allowance is needed; bounded deletion proofs independently permit two genuine removals.
proc run(prepared: PreparedAccumulationMachine, deleted = 2'u64): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(0),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig(),
    deletedAccounts = ElementLimit(deleted))

## Read the guest block price independently of the frozen458 host charge.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

## Keep the successful result owner bound before selecting its immutable regular/exceptional context.
proc context(done: AccumulationDispatchResult, dimension = AccumulationDimension.Regular): AccumulationEffectContext =
  assert done.error == AccumulationDispatchError.None
  done.effects.effectContext(dimension).value

## Decode one actual current record rather than trusting a cached balance projection.
proc account(owner: AccumulationEffectContext, service = 42'u32): ServiceMetadata =
  let entry = owner.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
      service))).value
  decodeServiceMetadata(entry.bytes, ByteLimit(ServiceMetadataBytes)).value.metadata

let valid = source()
let done = run(valid)
assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
let cpu = machineInfo(done.value.machine).value
assert uint64(cpu.registers[7]) == 0 and uint64(cpu.registers[8]) == high(uint64)
assert uint64(cpu.gas) == 100000-price(valid)-458 and uint64(cpu.gasDeficit) == 0
let regular = context(done)
let exceptional = context(done, AccumulationDimension.Exceptional)
assert uint64(account(regular).balance) == 190 and uint64(account(regular).supervisorBalance) == 9
assert uint64(account(exceptional).balance) == 100 and uint64(account(exceptional,
    99).supervisorBalance) == 13
assert regular.effectAccounts.value.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(
    99))).error == StateStoreError.MissingKey
assert regular.effectDeletedAccountCount.value == 1 and
    exceptional.effectDeletedAccountCount.value == 0
var copied = regular.effectDeletedAccountAt(AccumulationDeletedAccountIndex(0)).value
assert uint32(copied.service) == 99
copied.service = ServiceIndex(7)
assert uint32(regular.effectDeletedAccountAt(AccumulationDeletedAccountIndex(0)).value.service) == 99
assert normalizeAccumulationOutcome(done).value.outcomeContext.value.effectDeletedAccountCount.value == 1
for target in [0'u32, high(uint32)]:
  let completed = run(source(target = uint64(target), targetId = target))
  assert uint64(machineInfo(completed.value.machine).value.registers[7]) == 0
for target in [123'u64, 0x100000063'u64, high(uint64)]:
  let refused = run(source(target = target))
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-3
  assert uint64(account(context(refused)).balance) ==
      100 # Unknown full-width IDs cannot alias99 or credit the invoker.
let self = run(source(target = 42, includeTarget = false))
assert uint64(machineInfo(self.value.machine).value.registers[7]) == high(uint64)-8
for metadata in [junior(supervisor = 99), junior(supervisor = 123), junior(supervisorCreated = 10),
    junior(supervisorCreated = 12), junior(created = 128), junior(items = 1), junior(items = 2),
        junior(items = high(uint32))]:
  let refused = run(source(metadata = metadata))
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-8
  assert uint64(account(context(refused)).balance) == 100
  assert context(refused).effectDeletedAccountCount.value == 0
for slot in [0'u32, high(uint32)]:
  let refused = run(source(metadata = junior(created = slot), slot = slot))
  assert uint64(machineInfo(refused.value.machine).value.registers[7]) == high(uint64)-8
let malformed = StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(99)), value: @[0'u8])
assert run(source(includeTarget = false, extra = @[malformed])).error ==
    AccumulationDispatchError.MalformedState
for available in [0'u64, 457, 458, 459]:
  let completed = run(source(credit = price(valid)+available))
  let state = machineInfo(completed.value.machine).value
  if available < 458:
    assert completed.value.exit == StepExit.OutOfGas and uint64(state.gas) == 0
    assert uint64(state.gasDeficit) == 0 and uint64(state.registers[7]) == 99
    assert uint64(account(context(completed)).balance) == 100 # Unfunded execution performs no account work.
  else:
    assert completed.value.exit == StepExit.Halt and uint64(state.gas) == available-458
for writes in [0'u64, 1]:
  assert run(source(writes = writes)).error == AccumulationDispatchError.LimitExceeded
let exact = run(source(selfBalance = high(uint64)-90))
assert uint64(account(context(exact)).balance) == high(uint64)
for metadata in [junior(balance = high(uint64), supervised = 0),
    junior(balance = high(uint64)-100, supervised = 1)]:
  assert run(source(metadata = metadata)).error == AccumulationDispatchError.InvalidContext
let repeated = run(source(suffix = @[registerImmediate(7, 99), @[10'u8, 23], @[50'u8, 0]]))
assert uint64(machineInfo(repeated.value.machine).value.registers[7]) == high(uint64)-3
assert uint64(account(context(repeated)).balance) == 190 and context(
    repeated).effectDeletedAccountCount.value == 1
for checkpoint in [false, true]:
  let failed = run(source(suffix = (if checkpoint: @[@[10'u8, 19], @[0'u8]] else: @[@[0'u8]])))
  assert failed.value.exit == StepExit.Panic
  let selected = normalizeAccumulationOutcome(failed).value.outcomeContext.value
  assert uint64(account(selected).balance) == (if checkpoint: 190'u64 else: 100'u64)
  assert selected.effectDeletedAccountCount.value == (if checkpoint: 1 else: 0)
let secondTarget = serviceMetadataEntry(ServiceIndex(100), junior(), ByteLimit(
    ServiceMetadataBytes)).value
let pair = source(extra = @[secondTarget], suffix = @[registerImmediate(7, 100), @[10'u8, 23], @[50'u8, 0]])
let two = run(pair)
assert uint64(account(context(two)).balance) == 280 and context(
    two).effectDeletedAccountCount.value == 2
assert run(pair, deleted = 1).error == AccumulationDispatchError.LimitExceeded
let prepared = prepareAccumulationEffects(done.effects.effectsSource.value,
    deletedAccounts = ElementLimit(1)).value
assert recordAccumulationEject(default(AccumulationEffects), AccumulationEjectTarget(99),
    pvmParameters()).error == AccumulationEffectError.Uninitialized
assert recordAccumulationEject(prepared, AccumulationEjectTarget(99), default(Parameters)).error ==
    AccumulationEffectError.InvalidParameters
failHash(0)
let positive = recordAccumulationEject(prepared, AccumulationEjectTarget(99), pvmParameters())
assert positive.error == AccumulationEffectError.None
let publicationHashes = hashCalls()
assert publicationHashes > 0
for successful in 0..<publicationHashes:
  # Refuse every hash position, including the final parent hash, without assuming the old tombstone tree shape.
  failAfter(cint(successful))
  let failed = recordAccumulationEject(prepared, AccumulationEjectTarget(99), pvmParameters())
  assert failed.error == AccumulationEffectError.BackendFailure and hashCalls() == cint(successful+1)
  failHash(0)
  let initial = prepared.effectContext(AccumulationDimension.Regular).value
  assert uint64(account(initial).balance) == 100 and uint64(account(initial, 99).balance) == 77
failHash(1)
let unknown = recordAccumulationEject(prepared, AccumulationEjectTarget(high(uint64)),
    pvmParameters())
assert unknown.error == AccumulationEffectError.UnknownService and hashCalls() == 0
failHash(0)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let completed = run(valid)
  assert uint64(account(context(completed)).balance) ==
      190 # Every private CPU/map/proof successor must release after this iteration.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_eject", 1000, before, after)
echo "PVM accumulation eject passed"
echo "ARC_RELEASE cycles=1000 unchanged"
