# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_info_arc_release"}

## Authored info programs verify the independent fixed wire record, slicing, current state and ownership.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/codec/[bounded, composite, state_accounts, state_layout, state_trie, c2_records]
import ../../../src/state/[accumulation_dispatch, accumulation_machine, accumulation_invocation,
  accumulation_service, accumulation_context, accumulation_effects, store]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../support/[pvm_accumulation_program, pvm_accumulation_context, arc_evidence]

## Info must neither hash the metadata nor derive any storage namespace.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Prove fixed metadata reads never invoke a backend hash.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Fixed independent little-endian parameter fields choose exact deposit witnesses.
proc schedule(base = 10'u64, item = 2'u64, octet = 3'u64): Parameters =
  var wire = encodeParameters(pvmParameters())
  for field, value in [item, octet, base]:
    for i in 0..<8:
      wire[field*8+i] = byte((value shr (8*i)) and 255) # Exact E8 fields precede other validated parameters.
  decodeParameters(wire).value

## Each nonzero field has a distinct byte pattern; this fixture witnesses serialization, not chain reachability.
proc facts(): ServiceMetadata =
  var hash = default(array[32, byte])
  for i in 0..<32:
    hash[i] = byte((i*7+3) mod 256) # Fixed raw hash pattern distinguishes all offsets.
  ServiceMetadata(codeHash: CodeHash(hash), balance: AccountBalance(0x8877665544332211'u64),
    minimumAccumulationGas: Gas(0x1122334455667788'u64), minimumTransferGas: Gas(
        0xfedcba9876543210'u64),
    storageBytes: AccountStorageBytes(0x0102030405060708'u64), storageItems: AccountStorageItems(
        0x0a0b0c0d'u32),
    depositOffset: AccountBalance(0x0102030405060708'u64), created: AccountSlot(0x10203040'u32),
    lastAccumulation: AccountSlot(0x50607080'u32), parent: ServiceIndex(0xa0b0c0d0'u32))

## Other services share the authored metadata, but each exact full-width ID has its own map key.
proc entries(): seq[StateEntry] =
  result = @[]
  for service in [0'u32, 99, high(uint32)]:
    result.add(serviceMetadataEntry(ServiceIndex(service), facts(), ByteLimit(
        ServiceMetadataBytes)).value)

## Load all host inputs at full width and execute the real info host followed by halt.
proc source(target = 99'u64, destination = 196736'u64, offset = 0'u64, length = 112'u64,
    credit = 100000'u64, extra: seq[StateEntry] = entries()): PreparedAccumulationMachine =
  guestProgram([registerImmediate(7, target), registerImmediate(8, destination),
    registerImmediate(9, offset), registerImmediate(10, length), @[10'u8, 6], @[50'u8, 0]],
    credit, extra = extra, account = facts())

## Run only this prepared invocation with independent copy and engine ceilings.
proc run(prepared: PreparedAccumulationMachine, limit = 112'u64,
    parameters: Parameters = schedule()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, parameters,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig())

## Query prepaid code cost independently of the frozen 703 host cost.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

## Inspect the entire selected guest interval, including empty intervals at otherwise invalid addresses.
proc bytes(done: AccumulationDispatchResult, address, length: uint64): seq[byte] =
  readBytes(memoryOf(done.value.machine).value, MemoryAddress(address), MemoryLength(length),
      MemoryByteLimit(length)).value

let golden = @[
  3'u8, 10'u8, 17'u8, 24'u8, 31'u8, 38'u8, 45'u8, 52'u8, 59'u8, 66'u8, 73'u8, 80'u8,
  87'u8, 94'u8, 101'u8, 108'u8, 115'u8, 122'u8, 129'u8, 136'u8, 143'u8, 150'u8, 157'u8, 164'u8,
  171'u8, 178'u8, 185'u8, 192'u8, 199'u8, 206'u8, 213'u8, 220'u8, 0'u8, 0'u8, 0'u8, 0'u8,
  0'u8, 0'u8, 0'u8, 0'u8, 17'u8, 34'u8, 51'u8, 68'u8, 85'u8, 102'u8, 119'u8, 136'u8,
  0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 52'u8, 38'u8, 34'u8, 30'u8,
  8'u8, 6'u8, 4'u8, 2'u8, 136'u8, 119'u8, 102'u8, 85'u8, 68'u8, 51'u8, 34'u8, 17'u8,
  16'u8, 50'u8, 84'u8, 118'u8, 152'u8, 186'u8, 220'u8, 254'u8, 8'u8, 7'u8, 6'u8, 5'u8,
  4'u8, 3'u8, 2'u8, 1'u8, 13'u8, 12'u8, 11'u8, 10'u8, 8'u8, 7'u8, 6'u8, 5'u8,
  4'u8, 3'u8, 2'u8, 1'u8, 64'u8, 48'u8, 32'u8, 16'u8, 128'u8, 112'u8, 96'u8, 80'u8,
  208'u8, 192'u8, 176'u8, 160'u8]
assert golden.len == 112
for target in [0'u64, 99, uint64(high(uint32))]:
  let prepared = source(target)
  let done = run(prepared)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.registers[7]) == 112 and uint64(cpu.gas) == 100000-price(prepared)-703
  assert bytes(done, 196736, 112) == golden
  assert bytes(done, 196735, 1) == @[0'u8] and bytes(done, 196848, 1) == @[0'u8]
  assert uint64(cpu.registers[8]) == 196736 and uint64(cpu.registers[9]) == 0 and uint64(
      cpu.registers[10]) == 112
  for dimension in [AccumulationDimension.Regular, AccumulationDimension.Exceptional]:
    let context = done.effects.effectContext(dimension).value
    let before = prepared.machineBootstrap.value.bootstrapService.value.serviceState.value
    assert array[32, byte](context.effectAccounts.value.commitment.root) == array[32, byte](
        before.commitment.root)
    assert not context.effectInfo.value.hasYield and context.effectInfo.value.provisions == 0
for target in [42'u64, high(uint64)]:
  # Self uses the real program's code hash; all other bytes match the independent metadata fixture.
  let prepared = source(target)
  let done = run(prepared)
  let metadata = decodeServiceMetadata(prepared.machineBootstrap.value.bootstrapService.value.serviceState.value.lookup(
    chapterServiceKey(StateChapter(255), ServiceIndex(42))).value.bytes, ByteLimit(
        ServiceMetadataBytes)).value.metadata
  let expectedHash = array[32, byte](metadata.codeHash)
  let actual = bytes(done, 196736, 112)
  for i in 0..<112:
    assert actual[i] == (if i < 32: expectedHash[i] else: golden[i])
for offset in [0'u64, 1, 31, 32, 39, 40, 71, 72, 75, 76, 83, 84, 95, 112, 97, high(uint64)]:
  for requested in [0'u64, 1, 7, 112, high(uint64)]:
    # Clipping happens before narrowing; enormous requests retain a constant gas cost.
    let first = min(offset, 112'u64)
    let count = min(requested, 112-first)
    let destination = (if count == 0: high(uint64) else: 196736'u64)
    let done = run(source(destination = destination, offset = offset, length = requested), limit = count)
    assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
    assert uint64(machineInfo(done.value.machine).value.registers[7]) == 112
    var expected: seq[byte] = @[]
    for i in 0..<int(count):
      expected.add(golden[int(first)+i]) # Enumerate expected window independently of implementation slicing.
    assert bytes(done, destination, count) == expected
for target in [100'u64, 0x100000063'u64, high(uint64)-1]:
  let done = run(source(target, destination = high(uint64), length = high(uint64)), limit = 0)
  assert done.value.exit == StepExit.Halt and uint64(machineInfo(
      done.value.machine).value.registers[7]) == high(uint64)
for destination in [0'u64, 65536, 196608'u64+8192-48, 0x100000000'u64, high(uint64)]:
  let prepared = source(destination = destination)
  let done = run(prepared)
  assert done.value.exit == StepExit.Panic and uint64(machineInfo(
      done.value.machine).value.registers[7]) == 99
  assert uint64(machineInfo(done.value.machine).value.gas) == 100000-price(prepared)-703
  for page in [16'u32, 48, 49]:
    let before = pageImage(memoryOf(prepared.accumulationMachine.value).value, PageIndex(page)).value
    let after = pageImage(memoryOf(done.value.machine).value, PageIndex(page)).value
    assert before.bytes == after.bytes # No accessible prefix changes when any output byte is unwritable.
let crossing = run(source(destination = 196608'u64+4096-48))
assert bytes(crossing, 196608'u64+4096-48, 112) == golden
assert run(source(length = 112), limit = 95).error == AccumulationDispatchError.LimitExceeded
for available in [0'u64, 702, 703, 704]:
  let prototype = source()
  let prepared = source(credit = price(prototype)+available)
  let done = run(prepared)
  let cpu = machineInfo(done.value.machine).value
  if available < 703:
    assert done.value.exit == StepExit.OutOfGas and uint64(cpu.gasDeficit) == 0
    assert uint64(cpu.registers[7]) == 99 # No memory or account work precedes affordability.
  else:
    assert done.value.exit == StepExit.Halt and uint64(cpu.gas) == available-703
let corrupt = source(extra = @[StateEntry(key: chapterServiceKey(StateChapter(255), ServiceIndex(
    99)), value: @[0'u8])])
assert run(corrupt).error == AccumulationDispatchError.MalformedState
for firstByte in [1'u8, 128'u8]:
  var bad = newSeq[byte](ServiceMetadataBytes)
  bad[0] = firstByte # Unsupported schema and noncanonical version bytes cannot become a fixed host record.
  let malformed = source(extra = @[StateEntry(key: chapterServiceKey(StateChapter(255),
      ServiceIndex(99)), value: bad)])
  assert run(malformed).error == AccumulationDispatchError.MalformedState
let corruptPrice = price(corrupt)
let unfunded = source(credit = corruptPrice+702, extra = @[StateEntry(key: chapterServiceKey(
    StateChapter(255), ServiceIndex(99)), value: @[0'u8])])
assert run(unfunded, limit = 0).value.exit == StepExit.OutOfGas
let valid = source()
failHash(1)
let noBackend = run(valid)
assert noBackend.error == AccumulationDispatchError.None and hashCalls() == 0
assert bytes(noBackend, 196736, 112) == golden
failHash(0)

## Query exact threshold fields through the public immutable context API, independently of guest clipping.
proc minimum(metadata: ServiceMetadata, parameters: Parameters): AccumulationEffectResult[array[112, byte]] =
  let prepared = source(extra = @[serviceMetadataEntry(ServiceIndex(99), metadata, ByteLimit(
      ServiceMetadataBytes)).value])
  let context = run(prepared, parameters = parameters)
  if context.error != AccumulationDispatchError.None:
    return default(AccumulationEffectResult[array[112,
        byte]]) # Dedicated overflow assertions inspect dispatcher refusal separately.
  context.effects.effectContext(AccumulationDimension.Regular).value.effectAccountInfo(ServiceIndex(
      99), parameters)

## Independent E8 extraction for expected arithmetic, without using the encoder's shifts or field array.
proc threshold(bytes: array[112, byte]): uint64 =
  result = 0
  for i in countdown(63, 56):
    result = result*256+uint64(bytes[i]) # Exactly eight octets fit uint64, even at UINT64_MAX.

for witness in [(0'u64, 10'u64), (9'u64, 1'u64), (10'u64, 0'u64), (11'u64, 0'u64), (high(uint64), 0'u64)]:
  let (gratis, expected) = witness
  assert threshold(minimum(ServiceMetadata(depositOffset: AccountBalance(gratis)), schedule(10, 0,
      0)).value) == expected
let wide = ServiceMetadata(storageItems: AccountStorageItems(1), depositOffset: AccountBalance(high(uint64)))
assert threshold(minimum(wide, schedule(high(uint64), high(uint64), 0)).value) == high(uint64)
let overflow = source(extra = @[serviceMetadataEntry(ServiceIndex(99), ServiceMetadata(
    storageItems: AccountStorageItems(1)), ByteLimit(ServiceMetadataBytes)).value])
assert run(overflow, parameters = schedule(high(uint64), 1, 0)).error ==
    AccumulationDispatchError.MalformedState
let defaultContext = default(AccumulationEffectContext)
assert defaultContext.effectAccountInfo(ServiceIndex(42), schedule()).error ==
    AccumulationEffectError.Uninitialized
let initialized = run(valid).effects.effectContext(AccumulationDimension.Regular).value
assert initialized.effectAccountInfo(ServiceIndex(99), default(Parameters)).error ==
    AccumulationEffectError.InvalidParameters
assert initialized.effectAccountInfo(ServiceIndex(100), schedule()).error ==
    AccumulationEffectError.UnknownService
# A prior storage write changes the footprint and therefore info's dependent minimum balance.
let written = guestProgram([@[51'u8, 7, 255], registerImmediate(8, 65536), registerImmediate(9, 1),
    registerImmediate(10, 196608),
  registerImmediate(11, 3), @[10'u8, 5], registerImmediate(7, high(uint64)), registerImmediate(8, 196736),
  registerImmediate(9, 0), registerImmediate(10, 112), @[10'u8, 6], @[50'u8, 0]],
  100000, account = ServiceMetadata(balance: AccountBalance(10000)), spareEntries = 1)
let current = run(written)
assert current.error == AccumulationDispatchError.None and current.value.exit == StepExit.Halt
let currentRecord = current.effects.effectContext(
    AccumulationDimension.Regular).value.effectAccountInfo(ServiceIndex(42), schedule()).value
assert threshold(currentRecord) == 126 # 10+2+3*(34+1+3), after the actual preceding write.
assert bytes(current, 196736, 112) == @currentRecord
let before = getOccupiedMem()
for iteration in 0..<1000:
  let done = run(valid)
  assert bytes(done, 196736, 112) == golden # Repeated queries retain only immutable source state and release every memory successor.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_info", 1000, before, after)
echo "PVM accumulation info passed"
echo "ARC_RELEASE cycles=1000 unchanged"
