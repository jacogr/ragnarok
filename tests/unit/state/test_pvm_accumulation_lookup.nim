# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_accumulation_lookup_arc_release"}

## Authored lookup programs verify exact namespace selection, bounded suffix copying and atomic guest writes.
## Tests distinguish absent/empty state, full-width inputs, charged failures, source ownership and ARC release.

import std/[assertions, syncio]
import ../../../src/state/accumulation/[dispatch as accumulation_dispatch,
    machine as accumulation_machine, effects as accumulation_effects,
    context as accumulation_context, invocation as accumulation_invocation,
    service as accumulation_service]
import ../../../src/state/store
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/state/[layout as state_layout, accounts as state_accounts,
    service_values as state_service_values, trie as state_trie]
import ../../../src/codec/c2_records
import ../../../src/pvm/[machine, program, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/host/fetch as host_fetch
import ../../support/[pvm_accumulation_context, pvm_accumulation_program, arc_evidence]

## Refuse namespace hashing only after authentic fixture preparation has completed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Prove affordability/memory/account checks precede cryptographic namespace work.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

## Synthetic complete-map values use the exact raw identities placed in authored RO/RW memory.
## They witness dictionary lookup, not genesis reachability or recomputation of preimage-content hashes.
proc hash(first: byte): ServicePreimageHash =
  var bytes = default(array[32, byte])
  bytes[0] = first
  ServicePreimageHash(bytes)

## Pattern every value byte independently so clipping/order/truncation errors remain visible.
proc payload(size: int, seed = 11): seq[byte] =
  result = newSeq[byte](size)
  for i in 0..<size:
    result[i] = byte((i*17+seed) mod 256) # Authored extents are at most 9000, so native arithmetic is bounded.

## Self's 9000-byte value exceeds a short copy policy; present empty, other accounts and an orphan remain distinct.
proc entries(): seq[StateEntry] =
  result = @[]
  for service in [0'u32, 99'u32, high(uint32)]:
    result.add(serviceMetadataEntry(ServiceIndex(service), ServiceMetadata(), ByteLimit(
        ServiceMetadataBytes)).value) # Self comes from bootstrap.
  for item in [(42'u32, 73'u8, 9000), (42'u32, 0'u8, 0), (99'u32, 73'u8, 17),
      (99'u32, 81'u8, 32), (0'u32, 73'u8, 5), (high(uint32), 73'u8, 7), (100'u32, 73'u8, 1)]:
    let (service, identity, size) = item
    result.add(servicePreimageEntry(ServiceIndex(service), hash(identity), payload(size),
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(
          size))).value) # Raw keyed values, including an orphan.

## Encode every operand at full width; lookup uses r8 hash, r9 destination, r10 offset and r11 requested length.
proc source(target = 42'u64, address = 65536'u64, destination = 196736'u64,
    offset = 0'u64, length = 32'u64, credit = 100000'u64,
    extra: seq[StateEntry] = entries()): PreparedAccumulationMachine =
  guestProgram([registerImmediate(7, target), registerImmediate(8, address),
    registerImmediate(9, destination), registerImmediate(10, offset), registerImmediate(11, length),
    @[10'u8, 3], @[50'u8, 0]], credit, extra = extra)

## Copy limits cover only selected variable bytes; the fixed hash input has a separate 32-byte bound.
proc run(prepared: PreparedAccumulationMachine, limit = 64'u64): AccumulationDispatchResult =
  executeAccumulationMachine(prepared, pvmParameters(),
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
  assert uint64(cpu.gas) == 100000-price(prepared)-608
  var expected = payload(size)
  if expected.len > 32:
    expected.setLen(32) # Clip the independent expected source; r7 still reports its full untruncated length.
  checkBytes(done, 196736, expected)
  checkBytes(done, 196735, @[0'u8])
  checkBytes(done, uint64(196736+expected.len), @[0'u8])
  for i in 0..<13:
    if i != 7 and i < 8 or i == 12:
      assert uint64(cpu.registers[i]) == uint64(machineInfo(
          prepared.accumulationMachine.value).value.registers[i]) # No unrelated register changes.
  assert uint64(cpu.registers[8]) == 65536 and uint64(cpu.registers[9]) == 196736
  assert uint64(cpu.registers[10]) == 0 and uint64(cpu.registers[11]) == 32
  for dimension in [regular, exceptional]:
    let context = done.effects.effectContext(dimension).value
    assert not context.effectInfo.value.hasYield and context.effectInfo.value.provisions ==
        0 # Lookup has no implication effects.
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
# No whole-value copy is needed for either a one-byte window or a zero-byte length query on 9000 stored bytes.
let short = run(source(offset = 8999, length = 1), limit = 1)
checkBytes(short, 196736, @[payload(9000)[8999]])
assert uint64(machineInfo(short.value.machine).value.registers[7]) == 9000
let query = run(source(destination = high(uint64), length = 0), limit = 0)
assert query.value.exit == StepExit.Halt and uint64(machineInfo(
    query.value.machine).value.registers[7]) == 9000
# Present empty uses a zero hash from RO offset one; absent hashes/accounts use NONE through the same empty interval.
let empty = run(source(address = 65537, destination = high(uint64)), limit = 0)
assert empty.value.exit == StepExit.Halt and uint64(machineInfo(
    empty.value.machine).value.registers[7]) == 0
for target in [100'u64, 101, 0x10000002a'u64, high(uint64)-1]:
  let missing = run(source(target, destination = high(uint64)), limit = 0)
  assert missing.value.exit == StepExit.Halt and uint64(machineInfo(
      missing.value.machine).value.registers[7]) == none # Orphans cannot create accounts.
let absentHash = run(source(99, address = 65537, destination = high(uint64)), limit = 0)
assert absentHash.value.exit == StepExit.Halt and uint64(machineInfo(
    absentHash.value.machine).value.registers[7]) == none
for address in [0'u64, 69616, 0xffffffff'u64, 0x100010000'u64, high(uint64)]:
  # A hash-read error panics before missing-account handling, even with a zero-byte output request.
  let failed = run(source(100, address = address, length = 0), limit = 0)
  assert failed.value.exit == StepExit.Panic
  assert uint64(machineInfo(failed.value.machine).value.registers[7]) == 100
for destination in [65536'u64, 262144, 196608'u64+8192-16, 0xffffffff'u64, 0x100000000'u64, high(uint64)]:
  let prepared = source(destination = destination)
  let failed = run(prepared)
  assert failed.value.exit == StepExit.Panic and uint64(machineInfo(
      failed.value.machine).value.registers[7]) == 42
  assert uint64(machineInfo(failed.value.machine).value.gas) == 100000-price(prepared)-608
  for page in [16'u32, 48, 49]:
    let before = pageImage(memoryOf(prepared.accumulationMachine.value).value, PageIndex(page)).value
    let after = pageImage(memoryOf(failed.value.machine).value, PageIndex(page)).value
    assert before.bytes == after.bytes # Every output byte remains unchanged on cross-page/read-only/address failure.
let crossing = run(source(destination = 196608'u64+4096-16))
checkBytes(crossing, 196608'u64+4096-16, payload(32))
# Hash and output may overlap: hash input is fully captured before the atomic memory successor is constructed.
let overlapSource = source(99, address = 196608, destination = 196608)
let overlap = run(overlapSource)
checkBytes(overlap, 196608, payload(32))
assert readBytes(memoryOf(overlapSource.accumulationMachine.value).value, MemoryAddress(196608),
  MemoryLength(1), MemoryByteLimit(1)).value == @[81'u8]
for witness in [(0'u64, 600'u64), (1'u64, 601'u64), (1023'u64, 848'u64),
    (1024'u64, 848'u64), (1025'u64, 849'u64)]:
  let (requested, cost) = witness
  let prototype = source(length = requested)
  for available in [0'u64, cost-1, cost, cost+1]:
    let prepared = source(length = requested, credit = price(prototype)+available)
    let done = run(prepared, limit = 2048)
    let cpu = machineInfo(done.value.machine).value
    if available < cost:
      assert done.value.exit == StepExit.OutOfGas and uint64(cpu.gas) == 0
      assert uint64(cpu.gasDeficit) == 0 and uint64(cpu.registers[7]) ==
          42 # No hash/read/write before affordability.
    else:
      assert done.value.exit == StepExit.Halt and uint64(cpu.gas) == available-cost
      assert uint64(cpu.gasDeficit) == 0 and uint64(cpu.registers[7]) == 9000
# Gas uses full requested length even when offset clipping makes the copy empty.
let wideSource = source(destination = high(uint64), offset = high(uint64), length = high(uint64),
    credit = high(uint64))
let wide = run(wideSource, limit = 0)
assert wide.value.exit == StepExit.Halt and uint64(machineInfo(wide.value.machine).value.registers[7]) == 9000
assert uint64(machineInfo(wide.value.machine).value.gas) == high(uint64)-price(
    wideSource)-4467570830351532632'u64
let unfunded = source(address = high(uint64), length = high(uint64))
let debt = run(unfunded, limit = 0)
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
assert hashCalls() == 0 # Missing accounts do not attempt a guessed namespace lookup.
failHash(0)
let before = getOccupiedMem()
for iteration in 0..<1000:
  let done = run(valid)
  checkBytes(done, 196736, payload(32)) # Repeated calls use unchanged source memory and release every successor page/slice.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_accumulation_lookup", 1000, before, after)
echo "PVM accumulation lookup passed"
echo "ARC_RELEASE cycles=1000 unchanged"
