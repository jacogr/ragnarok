# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_read_arc_release"}

## Authored storage read programs verify raw namespaces, bounded slices and atomic guest writes.
## Distinguish absent/empty raw keys and values, full-width gas, source ownership and ARC release.

import std/[assertions, syncio]
import ../../../src/chain/parameters
import ../../../src/state/[accumulation_dispatch, accumulation_machine, accumulation_effects,
  accumulation_context, accumulation_invocation, accumulation_service, store]
import ../../../src/codec/[bounded, composite, state_layout, state_accounts, state_service_values,
  state_trie, c2_records]
import ../../../src/pvm/[machine, program, step, gas, host_fetch]
import ../../support/[pvm_accumulation_context, pvm_accumulation_program, arc_evidence]

## Refuse namespace hashing only after authentic fixture preparation has completed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Prove affordability/memory/account checks precede cryptographic namespace work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Synthetic complete-map values use exact raw keys placed in authored RO/RW memory.
## These dictionary witnesses do not claim genesis reachability.
proc rawKey(first: byte): seq[byte] =
  var bytes = default(array[32, byte])
  bytes[0] = first
  @bytes

## Pattern every value byte independently so clipping/order/truncation errors remain visible.
proc payload(size: int, seed = 11): seq[byte] =
  result = newSeq[byte](size)
  for i in 0..<size:
    result[i] = byte((i*17+seed) mod 256) # Authored extents are at most 9000, so native arithmetic is bounded.

## Self's long value, empty values and keys, other accounts and orphan mappings remain distinct.
proc entries(): seq[StateEntry] =
  result = @[]
  for service in [0'u32, 99'u32, high(uint32)]:
    result.add(serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(), ByteLimit(
        ServiceMetadataBytes)).value) # Self comes from bootstrap.
  for item in [(42'u32, 73'u8, 9000), (42'u32, 0'u8, 0), (99'u32, 73'u8, 17),
      (99'u32, 81'u8, 32), (0'u32, 73'u8, 5), (high(uint32), 73'u8, 7), (100'u32, 73'u8, 1)]:
    let (service, identity, size) = item
    result.add(serviceStorageEntry(ServiceIndex(service), rawKey(identity), payload(size),
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
          size))).value) # Raw keyed values, including an orphan.
  result.add(serviceStorageEntry(ServiceIndex(42), @[], @[3'u8, 4, 5],
    ServiceEntryLimits(keyBytes: ByteLimit(0), valueBytes: ByteLimit(3))).value)
  result.add(serviceStorageEntry(ServiceIndex(42), @[73'u8], @[9'u8],
    ServiceEntryLimits(keyBytes: ByteLimit(1), valueBytes: ByteLimit(1))).value)
  var identity = default(array[32, byte])
  identity[0] = 73
  result.add(servicePreimageEntry(ServiceIndex(42), ServicePreimageHash(identity), @[99'u8],
    ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(1))).value)

## Encode the raw key, destination and suffix operands at full register width.
proc source(target = 42'u64, address = 65536'u64, destination = 196736'u64,
    offset = 0'u64, length = 32'u64, keyLength = 32'u64, credit = 100000'u64,
    extra: seq[StateEntry] = entries()): PreparedAccumulationMachine =
  guestProgram([registerImmediate(7, target), registerImmediate(8, address),
    registerImmediate(9, keyLength), registerImmediate(10, destination), registerImmediate(11,
        offset),
    registerImmediate(12, length), @[10'u8, 4], @[50'u8, 0]], credit, extra = extra)

## Raw keys and selected value slices each obey the local copy ceiling.
proc run(prepared: PreparedAccumulationMachine, limit = 64'u64,
    parameters: Parameters = pvmParameters()): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, parameters,
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1),
      operand: OperandLimits(maxBytes: ByteLimit(132))), MemoryByteLimit(limit),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig())

## The actual prepaid code cost remains independent of the frozen expected host gas witnesses.
proc price(prepared: PreparedAccumulationMachine): uint64 =
  uint64(blockGas(programOf(prepared.accumulationMachine.value).value, CodeAddress(5),
      GasCycleLimit(1000)).value)

## Check all bytes in one selected guest interval; the caller has independently proved its expected extent.
proc checkBytes(done: AccumulationDispatchResult, address: uint64, expected: seq[byte]) =
  let copied = readBytes(memoryOf(done.value.machine).value, MemoryAddress(address),
    MemoryLength(uint64(expected.len)), MemoryByteLimit(uint64(expected.len)))
  assert copied.error == MachineError.None and copied.value == expected

let regular = AccumulationDimension.Regular
let exceptional = AccumulationDimension.Exceptional
let none = high(uint64)
for witness in [(0'u64, 5), (42'u64, 9000), (99'u64, 17), (uint64(high(uint32)), 7), (high(uint64), 9000)]:
  let (target, size) = witness
  let prepared = source(target)
  let done = run(prepared)
  assert done.error == AccumulationDispatchError.None and done.value.exit == StepExit.Halt
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.registers[7]) == uint64(size)
  assert uint64(cpu.gas) == 100000-price(prepared)-2470
  var expected = payload(size)
  if expected.len > 32:
    expected.setLen(32) # Clip the independent expected source; r7 still reports its full untruncated length.
  checkBytes(done, 196736, expected)
  checkBytes(done, 196735, @[0'u8])
  checkBytes(done, uint64(196736+expected.len), @[0'u8])
  for i in 0..<13:
    if i < 7:
      assert uint64(cpu.registers[i]) == uint64(machineInfo(
          prepared.accumulationMachine.value).value.registers[i]) # No unrelated register changes.
  assert uint64(cpu.registers[8]) == 65536 and uint64(cpu.registers[9]) == 32
  assert uint64(cpu.registers[10]) == 196736 and uint64(cpu.registers[11]) == 0
  assert uint64(cpu.registers[12]) == 32
  for dimension in [regular, exceptional]:
    let context = done.effects.effectContext(dimension).value
    assert not context.effectInfo.value.hasYield and context.effectInfo.value.provisions ==
        0 # Read has no implication effects.
    let prior = prepared.machineBootstrap.value.bootstrapService.value.serviceState.value
    let after = context.effectInitialContext.value.contextAccounts.value
    assert array[32, byte](prior.commitment.root) == array[32, byte](after.commitment.root)
  assert uint64(machineInfo(prepared.accumulationMachine.value).value.gas) == 100000
for offset in [0'u64, 1, 16, 17, 18, high(uint64)]:
  for requested in [0'u64, 1, 32]:
    # Offset is clipped before length subtraction; huge offsets create an empty interval at any pointer.
    let destination = (if offset >= 17 or requested == 0: high(uint64) else: 196736'u64)
    let done = run(source(99, destination = destination, offset = offset, length = requested))
    assert done.value.exit == StepExit.Halt and uint64(machineInfo(
        done.value.machine).value.registers[7]) == 17
    let first = min(offset, 17'u64)
    let copied = min(requested, 17'u64-first)
    var expected: seq[byte] = @[]
    for i in 0..<int(copied):
      expected.add(payload(17)[int(first)+i]) # Independently enumerate the clipped suffix.
    checkBytes(done, destination, expected)
# Short windows and length queries avoid copying the entire stored value.
let short = run(source(offset = 8999, length = 1), limit = 32)
checkBytes(short, 196736, @[payload(9000)[8999]])
assert uint64(machineInfo(short.value.machine).value.registers[7]) == 9000
let query = run(source(destination = high(uint64), length = 0), limit = 32)
assert query.value.exit == StepExit.Halt and uint64(machineInfo(
    query.value.machine).value.registers[7]) == 9000
# Present empty uses a zero-filled key from RO offset one; absent keys/accounts use NONE through the same empty interval.
let empty = run(source(address = 65537, destination = high(uint64)), limit = 32)
assert empty.value.exit == StepExit.Halt and uint64(machineInfo(
    empty.value.machine).value.registers[7]) == 0
for target in [100'u64, 101, 0x10000002a'u64, high(uint64)-1]:
  let missing = run(source(target, destination = high(uint64)), limit = 32)
  assert missing.value.exit == StepExit.Halt and uint64(machineInfo(
      missing.value.machine).value.registers[7]) == none # Orphans cannot create accounts.
let absentKey = run(source(99, address = 65537, destination = high(uint64)), limit = 32)
assert absentKey.value.exit == StepExit.Halt and uint64(machineInfo(
    absentKey.value.machine).value.registers[7]) == none
for address in [0'u64, 69616, 0xffffffff'u64, 0x100010000'u64, high(uint64)]:
  # A key-read error panics before missing-account handling, even with a zero-byte output request.
  let failed = run(source(100, address = address, length = 0), limit = 32)
  assert failed.value.exit == StepExit.Panic
  assert uint64(machineInfo(failed.value.machine).value.registers[7]) == 100
for destination in [65536'u64, 262144, 196608'u64+8192-16, 0xffffffff'u64, 0x100000000'u64, high(uint64)]:
  let prepared = source(destination = destination)
  let failed = run(prepared)
  assert failed.value.exit == StepExit.Panic and uint64(machineInfo(
      failed.value.machine).value.registers[7]) == 42
  assert uint64(machineInfo(failed.value.machine).value.gas) == 100000-price(prepared)-2470
  for page in [16'u32, 48, 49]:
    let before = pageImage(memoryOf(prepared.accumulationMachine.value).value, PageIndex(page)).value
    let after = pageImage(memoryOf(failed.value.machine).value, PageIndex(page)).value
    assert before.bytes == after.bytes # Every output byte remains unchanged on cross-page/read-only/address failure.
let crossing = run(source(destination = 196608'u64+4096-16))
checkBytes(crossing, 196608'u64+4096-16, payload(32))
# Key and output may overlap: raw input is fully captured before the atomic memory successor is constructed.
let overlapSource = source(99, address = 196608, destination = 196608)
let overlap = run(overlapSource)
checkBytes(overlap, 196608, payload(32))
assert readBytes(memoryOf(overlapSource.accumulationMachine.value).value, MemoryAddress(196608),
  MemoryLength(1), MemoryByteLimit(1)).value == @[81'u8]
for witness in [(0'u64, 2462'u64), (1'u64, 2463'u64), (1023'u64, 2710'u64),
    (1024'u64, 2710'u64), (1025'u64, 2711'u64)]:
  let (requested, cost) = witness
  let prototype = source(length = requested)
  for available in [0'u64, cost-1, cost, cost+1]:
    let prepared = source(length = requested, credit = price(prototype)+available)
    let done = run(prepared, limit = 2048)
    let cpu = machineInfo(done.value.machine).value
    if available < cost:
      assert done.value.exit == StepExit.OutOfGas and uint64(cpu.gas) == 0
      assert uint64(cpu.gasDeficit) == 0 and uint64(cpu.registers[7]) ==
          42 # No key/read/write before affordability.
    else:
      assert done.value.exit == StepExit.Halt and uint64(cpu.gas) == available-cost
      assert uint64(cpu.gasDeficit) == 0 and uint64(cpu.registers[7]) == 9000
# Gas uses full requested length even when offset clipping makes the copy empty.
let wideSource = source(destination = high(uint64), offset = high(uint64), length = high(uint64),
    credit = high(uint64))
let wide = run(wideSource, limit = 32)
assert wide.value.exit == StepExit.Halt and uint64(machineInfo(wide.value.machine).value.registers[7]) == 9000
assert uint64(machineInfo(wide.value.machine).value.gas) == high(uint64)-price(
    wideSource)-4467570830351534494'u64
let unfunded = source(address = high(uint64), length = high(uint64))
let debt = run(unfunded, limit = 32)
assert debt.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(debt.value.machine).value.gasDeficit) == 0
assert run(source(length = 65), limit = 64).error == AccumulationDispatchError.LimitExceeded
let malformed = source(99, extra = @[StateEntry(key: chapterServiceKey(StateChapter(255),
    ServiceIndex(99)), value: @[0'u8])])
assert run(malformed).error == AccumulationDispatchError.InvalidContext
let valid = source()
failHash(1)
assert run(valid).error == AccumulationDispatchError.BackendFailure
assert hashCalls() == 1
failHash(0)
let unknown = source(100)
failHash(1)
assert uint64(machineInfo(run(unknown).value.machine).value.registers[7]) == none
assert hashCalls() == 0 # Missing accounts do not attempt a guessed namespace read.
failHash(0)
# Empty raw keys are independent from zero-filled nonempty keys and permit zero-copy length queries.
let emptyKey = run(source(address = high(uint64), keyLength = 0, length = 0,
    destination = high(uint64)), limit = 0)
assert emptyKey.value.exit == StepExit.Halt and uint64(machineInfo(
    emptyKey.value.machine).value.registers[7]) == 3
assert run(source(keyLength = 33), limit = 32).error == AccumulationDispatchError.LimitExceeded
# The same first byte at a different raw key length names a different value, never a preimage.
let oneByteKey = run(source(keyLength = 1, length = 1), limit = 1)
assert oneByteKey.error == AccumulationDispatchError.None
assert uint64(machineInfo(oneByteKey.value.machine).value.registers[7]) == 1
checkBytes(oneByteKey, 196736, @[9'u8])
# Key preflight crosses readable pages atomically and refuses a missing final page.
let crossingKey = run(source(address = 196608'u64+4096-16))
assert crossingKey.error == AccumulationDispatchError.None and crossingKey.value.exit == StepExit.Halt
assert uint64(machineInfo(crossingKey.value.machine).value.registers[7]) == 0
let brokenKey = run(source(address = 196608'u64+8192-16))
assert brokenKey.error == AccumulationDispatchError.None and brokenKey.value.exit == StepExit.Panic
# Freeze independent integer-arithmetic witnesses for key rounding and full-width limb carry/debt.
for witness in [(0'u64, 2407'u64), (1'u64, 2409'u64), (1023'u64, 4142'u64),
    (1024'u64, 4143'u64), (1025'u64, 4145'u64)]:
  let (size, cost) = witness
  let prototype = source(keyLength = size, length = 0)
  let prepared = source(keyLength = size, length = 0, credit = price(prototype)+cost-1)
  let done = run(prepared, limit = 0)
  assert done.value.exit == StepExit.OutOfGas
  assert uint64(machineInfo(done.value.machine).value.gasDeficit) == 0
# A cost above uint64 with funded low-limb borrow still yields a representable exact debt.
let hugePrototype = source(keyLength = 0xb000000000000000'u64, length = 0)
let huge = source(keyLength = 0xb000000000000000'u64, length = 0, credit = high(uint64))
let borrowed = run(huge, limit = 0)
assert borrowed.error == AccumulationDispatchError.None and borrowed.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(borrowed.value.machine).value.gasDeficit) ==
    0 # Frozen from unbounded integer arithmetic.
# Adding the full value term also crosses the cost limb without losing its carry.
let combinedPrototype = source(keyLength = 0xb000000000000000'u64, length = high(uint64))
let combined = run(source(keyLength = 0xb000000000000000'u64, length = high(uint64),
    credit = high(uint64)), limit = 0)
assert combined.error == AccumulationDispatchError.None and combined.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(combined.value.machine).value.gasDeficit) ==
    0
assert run(source(keyLength = high(uint64), length = high(uint64)), limit = 0).value.exit ==
    StepExit.OutOfGas
# Both cost terms participate at the exact signed-negative limit; one less gas refuses locally.
let boundaryPrototype = source(keyLength = 6917529027641081856'u64,
    length = 2305843009213693952'u64)
let boundaryCredit = 3062447746611939687'u64+price(boundaryPrototype)
let boundary = run(source(keyLength = 6917529027641081856'u64, length = 2305843009213693952'u64,
    credit = boundaryCredit), limit = 0)
assert boundary.error == AccumulationDispatchError.None and boundary.value.exit == StepExit.OutOfGas
assert uint64(machineInfo(boundary.value.machine).value.gasDeficit) == 0
assert run(source(keyLength = 6917529027641081856'u64, length = 2305843009213693952'u64,
    credit = boundaryCredit-1), limit = 0).value.exit == StepExit.OutOfGas
# Authored finite deposits permit the actual writes; the default read-only fixture has maximal fees.
var depositWire = encodeParameters(pvmParameters())
for field, amount in [2'u64, 3, 10]:
  for i in 0..<8:
    # Preserve every other explicit parameter with one independently encoded E8 field.
    depositWire[field*8+i] = byte((amount shr (8*i)) and 255)
let deposits = decodeParameters(depositWire).value

# A read after write observes the current regular map even after checkpoint divergence.
# Population changes are upstream of this invocation; the observer must not retain its bootstrap map.
for checkpoint in [false, true]:
  for panic in [false, true]:
    # Keep the raw key stable while replacing three authored bytes with their two-byte suffix.
    var instructions = @[@[51'u8, 7, 255], registerImmediate(8, 65536), @[51'u8, 9, 1],
      registerImmediate(10, 196608), @[51'u8, 11, 3], @[10'u8, 5],
      @[51'u8, 7, 255], registerImmediate(10, 196736), @[51'u8, 11, 0],
      @[51'u8, 12, 3], @[10'u8, 4]]
    if checkpoint:
      instructions.add(@[10'u8, 19]) # Only the first write becomes the exceptional account state.
    instructions.add(@[51'u8, 7, 255])
    instructions.add(registerImmediate(10, 196609))
    instructions.add(@[51'u8, 11, 2])
    instructions.add(@[10'u8, 5])
    instructions.add(@[51'u8, 7, 255])
    instructions.add(registerImmediate(10, 196752))
    instructions.add(@[51'u8, 11, 0])
    instructions.add(@[10'u8, 4])
    if panic:
      instructions.add(@[0'u8]) # Exceptional termination must not rewind already observed guest memory.
    else:
      instructions.add(@[50'u8, 0]) # Regular termination retains the same two independent read observations.
    let prepared = guestProgram(instructions, 100000,
      account = ServiceMetadata(balance: AccountBalance(10000)), spareEntries = 1,
      writable = @[81'u8, 82, 83])
    let done = run(prepared, parameters = deposits)
    assert done.error == AccumulationDispatchError.None, "write/read execution completes"
    assert done.value.exit == (if panic: StepExit.Panic else: StepExit.Halt)
    checkBytes(done, 196736, @[81'u8, 82, 83])
    checkBytes(done, 196752, @[82'u8, 83, 0]) # The shorter replacement cannot leak the old trailing byte.
    assert uint64(machineInfo(done.value.machine).value.registers[7]) == 2
    let key = serviceStorageKey(ServiceIndex(42), @[73'u8], ByteLimit(1)).value
    let regularMap = done.effects.effectContext(regular).value.effectAccounts.value
    assert regularMap.lookup(key).value.bytes == @[82'u8, 83]
    let exceptionalMap = done.effects.effectContext(exceptional).value.effectAccounts.value
    if checkpoint:
      assert exceptionalMap.lookup(key).value.bytes == @[81'u8, 82, 83] # Read never mutates the saved checkpoint.
    else:
      assert exceptionalMap.lookup(key).error == StateStoreError.MissingKey # Reads cannot create exceptional writes.
    let prior = prepared.machineBootstrap.value.bootstrapService.value.serviceState.value
    assert prior.lookup(key).error == StateStoreError.MissingKey # Source accounts remain immutable after both writes.
    assert readBytes(memoryOf(prepared.accumulationMachine.value).value, MemoryAddress(196736),
      MemoryLength(3), MemoryByteLimit(3)).value == @[0'u8, 0, 0]
let before = getOccupiedMem()
for iteration in 0..<1000:
  let done = run(valid)
  checkBytes(done, 196736, payload(32)) # Repeated calls use unchanged source memory and release every successor page/slice.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_read", 1000, before, after)
echo "PVM accumulation read passed"
echo "ARC_RELEASE cycles=1000 unchanged"
