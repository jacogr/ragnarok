# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent standard-initialization witnesses for envelope framing, page layout and CPU entry.
## Tests padding, permissions, limits, immutable ownership, executable initialization and ARC release.

# @@Verification={"arc": "pvm_initialization_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, initialize, gas, step]
import ../../support/arc_evidence

# Fixed-width fixture encoding is independent of the initializer's decoder.
proc appendFixed(bytes: var seq[byte], value: uint64, width: int) =
  for i in 0..<width:
    # All values are explicitly constrained by the test's chosen header field.
    bytes.add(byte((value shr (8 * i)) and 255))

# Build a JAM envelope with caller-controlled data, heap pages, stack and raw PVM bytes.
proc envelope(ro, rw, code: openArray[byte], extra, stack: uint64): seq[byte] =
  result = @[]
  appendFixed(result, uint64(ro.len), 3)
  appendFixed(result, uint64(rw.len), 3)
  appendFixed(result, extra, 2)
  appendFixed(result, stack, 3)
  for value in ro:
    # Serialized sections are adjacent; address-space guard zones are never serialized.
    result.add(value)
  for value in rw:
    # Writable payload follows the entire read-only payload.
    result.add(value)
  appendFixed(result, uint64(code.len), 4)
  for value in code:
    # The embedded program owns its own canonical framing and opcode mask.
    result.add(value)

# Local policy is intentionally small; individual tests override exact boundaries.
func policy(pages: uint32): InitializationLimits =
  InitializationLimits(envelope: InitializationByteLimit(1000000), program: ProgramByteLimit(100),
    jumps: JumpCountLimit(0), pages: PageLimit(pages))

# Exercise the common entry/gas selection without hiding production result selection from tests.
proc start(blob, args: openArray[byte], pages: uint32): InitializationResult =
  initializeMachine(blob, args, CodeAddress(0), MachineGas(100), policy(pages))

# Verify a whole page's permission and every byte, including inaccessible padding within its zone.
proc checkPage(memory: Memory, address: uint32, access: PageAccess, payload: openArray[byte]) =
  let image = pageImage(memory, PageIndex(address div 4096)).value
  assert image.access == access
  for i in 0..<4096:
    # Caller supplies only the initialized prefix; the rest must be zero-filled.
    let expected = (if i < payload.len: payload[i] else: 0'u8)
    assert image.bytes[i] == expected

let trap = @[0'u8, 0, 1, 0, 1]
let empty = envelope([], [], trap, 0, 0)
let minimal = start(empty, [], 0).value
let cpu = machineInfo(minimal).value
assert uint64(cpu.pc) == 0 and uint64(cpu.gas) == 100 and not cpu.blockCharged
for i in 0..<13:
  # All register slots are checked, including the nine prescribed zero values.
  let expected = (if i == 0: 0xffff0000'u64 elif i == 1: 0xfefe0000'u64
    elif i == 7: 0xfeff0000'u64 else: 0'u64)
  assert uint64(cpu.registers[i]) == expected
assert pageImage(memoryOf(minimal).value, PageIndex(16)).value.access == PageAccess.Inaccessible
assert start(empty, [], 0).error == InitializationError.None
# An all-empty initialized memory is valid; a guest trap still executes normally.
assert execute(minimal, ExecutionStepLimit(1), GasCycleLimit(100)).value.exit == StepExit.Panic
# Initial r0 is the normative halt sentinel, usable directly by jump_ind.
let halt = start(envelope([], [], [0'u8, 0, 2, 50, 0, 1], 0, 0), [], 0).value
assert execute(halt, ExecutionStepLimit(1), GasCycleLimit(100)).value.exit == StepExit.Halt

# Every final member of T is raw-valid, but only five need no fallthrough at JAM preparation.
for opcode in [0'u8, 1, 40, 50, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
    170, 171, 172, 173, 174, 175, 180]:
  let accepted = opcode in {0'u8, 40'u8, 50'u8, 80'u8, 180'u8}
  for padding in [0, 1, 24]:
    # Literal opcode boundaries cover zero-padded operands and the exact skip cap.
    var raw = @[0'u8, 0, byte(4 + padding), 51, 7, 7, opcode]
    for index in 0..<padding: raw.add(0)
    raw.add(9)
    for index in 1..<((4 + padding + 7) div 8): raw.add(0)
    assert decodeProgram(raw, CodeAddress(0), ProgramByteLimit(100), JumpCountLimit(0)).error ==
        ProgramError.None
    let input = envelope([11'u8], [22'u8], raw, 0, 0)
    let source = input
    let prepared = start(input, [], 2)
    assert prepared.error == (if accepted: InitializationError.None else:
      InitializationError.InvalidProgram)
    assert input == source
    if accepted:
      # Preparation never executes even a successful load prefix; all initialized registers survive.
      assert uint64(machineInfo(prepared.value).value.registers[7]) == 0xfeff0000'u64
      assert uint64(load(memoryOf(prepared.value).value, MemoryAddress(196608), AccessWidth(
          1)).value) == 22
    # Whole-module rejection also applies when the final instruction is unreachable from entry.
    raw[3] = 0
    assert start(envelope([], [], raw, 0, 0), [], 0).error ==
        (if accepted: InitializationError.None else: InitializationError.InvalidProgram)

# The conditional's taken destination is valid entry0; missing fallthrough alone causes refusal.
let finalConditional = [0'u8, 0, 6, 51, 7, 7, 170, 0, 253, 9]
assert start(envelope([], [], finalConditional, 0, 0), [], 0).error ==
    InitializationError.InvalidProgram
# A successor-present conditional and fallthrough remain valid at preparation.
for raw in [@[0'u8, 0, 5, 51, 7, 7, 1, 0, 25],
    @[0'u8, 0, 7, 51, 7, 7, 170, 0, 253, 0, 73]]:
  assert start(envelope([], [], raw, 0, 0), [], 0).error == InitializationError.None
# Static-target validity remains a runtime check; this exception does not add eager branch checks.
assert start(envelope([], [], [0'u8, 0, 2, 40, 127, 1], 0, 0), [], 0).error ==
    InitializationError.None

# Exact truncations cover header fields, payload, program length and embedded program bytes.
for length in 0..<empty.len:
  let rejected = start(empty.toOpenArray(0, length - 1), [], 0)
  assert rejected.error == InitializationError.InvalidEnvelope
var trailing = empty
trailing.add(0)
assert start(trailing, [], 0).error == InitializationError.InvalidEnvelope
assert start(envelope([], [], [], 0, 0), [], 0).error == InitializationError.InvalidProgram
assert start(envelope([], [], [255'u8], 0, 0), [], 0).error == InitializationError.InvalidProgram
assert initializeMachine(empty, [], CodeAddress(1), MachineGas(0), policy(0)).error ==
  InitializationError.InvalidProgram
var limits = policy(0)
limits.envelope = InitializationByteLimit(uint64(empty.len - 1))
assert initializeMachine(empty, [], CodeAddress(0), MachineGas(0), limits).error ==
    InitializationError.LimitExceeded
limits.envelope = InitializationByteLimit(uint64(empty.len))
limits.program = ProgramByteLimit(4)
assert initializeMachine(empty, [], CodeAddress(0), MachineGas(0), limits).error ==
    InitializationError.LimitExceeded
# A zero-width jump table still consumes logical jump budget.
assert start(envelope([], [], [1'u8, 0, 1, 0, 1], 0, 0), [], 0).error ==
    InitializationError.LimitExceeded
# Maximum declared zero-fill sizes must be rejected without first allocating their pages.
assert start(envelope([], [], trap, 65535, 0xffffff), [], 1).error ==
    InitializationError.LimitExceeded
for field in [0, 3]:
  # A maximal declared payload cannot fit in the small fixture, independently of integer conversion.
  var malformed = empty
  for i in 0..<3: malformed[field + i] = 255
  assert start(malformed, [], 0).error == InitializationError.InvalidEnvelope
var badCodeLength = empty
for i in 11..<15:
  # The fixed 32-bit program extent cannot wrap or turn into a negative host index.
  badCodeLength[i] = 255
assert start(badCodeLength, [], 0).error == InitializationError.InvalidEnvelope

# Independent expected addresses exercise both page and major-zone rounding transitions.
for size in [1, 4095, 4096, 4097, 65535, 65536, 65537]:
  var payload = newSeq[byte](size)
  for i in 0..<size:
    # Nonzero patterned bytes expose copies from the wrong serialized section or offset.
    payload[i] = byte(1 + i mod 251)
  let pageCount = (size - 1) div 4096 + 1
  let zoneCount = (size - 1) div 65536 + 1
  let blob = envelope(payload, payload, trap, 1, uint64(size))
  let needed = uint32(pageCount * 4 + 1)
  assert start(blob, payload, needed - 1).error == InitializationError.LimitExceeded
  let machine = start(blob, payload, needed).value
  let memory = memoryOf(machine).value
  let rwStart = uint32(131072 + zoneCount * 65536)
  let stackStart = 0xfefe0000'u32 - uint32(pageCount * 4096)
  for page in 0..<pageCount:
    # Every page boundary is checked across each region, including the partially filled last page.
    let first = page * 4096
    let last = min(size, first + 4096) - 1
    checkPage(memory, 65536'u32 + uint32(first), PageAccess.ReadOnly, payload.toOpenArray(first, last))
    checkPage(memory, rwStart + uint32(first), PageAccess.ReadWrite, payload.toOpenArray(first, last))
    checkPage(memory, stackStart + uint32(first), PageAccess.ReadWrite, [])
    checkPage(memory, 0xfeff0000'u32 + uint32(first), PageAccess.ReadOnly, payload.toOpenArray(
        first, last))
  checkPage(memory, rwStart + uint32(pageCount * 4096), PageAccess.ReadWrite, [])
  for missing in [65536'u32 - 4096, 65536'u32 + uint32(pageCount * 4096),
      rwStart - 4096, rwStart + uint32((pageCount + 1) * 4096), stackStart - 4096,
      0xfefe0000'u32, 0xfeff0000'u32 - 4096, 0xfeff0000'u32 + uint32(pageCount * 4096)]:
    # Guard zones are absent from sparse memory rather than spuriously mapped as zero-filled pages.
    assert pageImage(memory, PageIndex(missing div 4096)).value.access == PageAccess.Inaccessible
  assert uint64(machineInfo(machine).value.registers[8]) == uint64(size)
  assert store(memory, MemoryAddress(65536), AccessWidth(1), RegisterValue(9)).error ==
      MachineError.Fault
  assert store(memory, MemoryAddress(0xfeff0000), AccessWidth(1), RegisterValue(9)).error ==
      MachineError.Fault
  assert store(memory, MemoryAddress(rwStart), AccessWidth(1), RegisterValue(9)).error ==
      MachineError.None
  assert store(memory, MemoryAddress(stackStart), AccessWidth(1), RegisterValue(9)).error ==
      MachineError.None

# Empty regions map no pages, while an empty writable payload may still request zero-filled heap.
for mask in 0..<16:
  let ro = (if (mask and 1) != 0: @[21'u8] else: newSeq[byte](0))
  let rw = (if (mask and 2) != 0: @[22'u8] else: newSeq[byte](0))
  let stack = (if (mask and 4) != 0: 1'u64 else: 0'u64)
  let args = (if (mask and 8) != 0: @[23'u8] else: newSeq[byte](0))
  let count = uint32(ro.len + rw.len + int(stack) + args.len + 1)
  let memory = memoryOf(start(envelope(ro, rw, trap, 1, stack), args, count).value).value
  let rwStart = (if ro.len == 0: 131072'u32 else: 196608'u32)
  checkPage(memory, rwStart + uint32(rw.len * 4096), PageAccess.ReadWrite, [])
  if ro.len == 0:
    # Empty serialized data must not manufacture a readable major zone.
    checkPage(memory, 65536, PageAccess.Inaccessible, [])
  if stack == 0:
    # The initial SP does not imply an allocated stack when its declared length is zero.
    checkPage(memory, 0xfefdf000'u32, PageAccess.Inaccessible, [])
  if args.len == 0:
    # Argument pointer is still initialized, but the page remains inaccessible.
    checkPage(memory, 0xfeff0000'u32, PageAccess.Inaccessible, [])

# Caller-selected valid entry and full-width gas are retained verbatim, initially uncharged.
let nonzero = initializeMachine(envelope([], [], [0'u8, 0, 2, 0, 0, 3], 0, 0), [],
  CodeAddress(1), MachineGas(high(uint64)), policy(0)).value
assert uint64(machineInfo(nonzero).value.pc) == 1
assert uint64(machineInfo(nonzero).value.gas) == high(uint64)

# Current paper and JAM initialization agree on the third register byte's low nibble.
block:
  let bytes = @[0'u8, 0, 11, 51, 1, 7, 51, 2, 11, 190, 33, 16, 50, 0, 73, 2]
  let initialized = start(envelope([], [], bytes, 0, 0), [], 0).value
  let owned = programOf(initialized).value
  assert byte(instruction(owned, CodeAddress(6)).value.d) == 0
  let jam = execute(initialized, ExecutionStepLimit(4), GasCycleLimit(1000)).value
  assert jam.exit == StepExit.Panic and uint64(machineInfo(jam.machine).value.registers[0]) == 18
  assert uint64(machineInfo(jam.machine).value.registers[12]) == 0
  # Raw capture follows the same current-paper register rule and reaches the same invalid dynamic target.
  let raw = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(100), JumpCountLimit(0)).value
  let paperSource = captureMachine(raw, memoryOf(initialized).value, machineInfo(
      initialized).value).value
  let paper = execute(paperSource, ExecutionStepLimit(4), GasCycleLimit(1000)).value
  assert paper.exit == StepExit.Panic and uint64(machineInfo(paper.machine).value.registers[0]) == 18
  assert uint64(machineInfo(paper.machine).value.registers[12]) == 0
  assert uint64(machineInfo(initialized).value.registers[0]) == 0xffff0000'u64

# Seeded mutations exercise untrusted fields and code without permitting a partial success owner.
var seed = 12345'u64
for iteration in 0..<512:
  # Explicit modular arithmetic keeps the independent deterministic generator in a bounded domain.
  seed = (seed * 1664525 + 1013904223) mod 0x100000000'u64
  var mutated = empty
  mutated[int(seed mod uint64(mutated.len))] = byte((seed shr 16) and 255)
  let checked = start(mutated, [], 8)
  assert checked.error != InitializationError.Uninitialized
  if checked.error == InitializationError.None:
    # Every successful mutation must retain a usable, fully owned program and machine.
    assert machineInfo(checked.value).error == MachineError.None
    assert instruction(programOf(checked.value).value, CodeAddress(0)).error == ProgramError.None

# The protocol argument maximum is accepted when policy permits; one extra byte is always rejected.
block:
  var arguments = newSeq[byte](0x1000000)
  arguments[arguments.len - 1] = 99
  let initialized = start(empty, arguments, 4096).value
  let memory = memoryOf(initialized).value
  assert uint64(load(memory, MemoryAddress(0xfffeffff), AccessWidth(1)).value) == 99
  assert pageImage(memory, PageIndex(0xffff0000'u32 div 4096)).value.access ==
      PageAccess.Inaccessible
  arguments.add(0)
  assert start(empty, arguments, 4097).error == InitializationError.ArgumentsTooLarge

# A complete invocation lifetime checks independent snapshots after mutating caller-owned inputs.
proc cycle() =
  var blob = envelope([7'u8], [11'u8], [0'u8, 0, 1, 0, 1], 1, 1)
  var args = @[13'u8]
  let machine = start(blob, args, 5).value
  blob[11] = 99
  blob[12] = 88
  blob[20] = 1
  args[0] = 77
  let memory = memoryOf(machine).value
  assert uint64(load(memory, MemoryAddress(65536), AccessWidth(1)).value) == 7
  assert uint64(load(memory, MemoryAddress(196608), AccessWidth(1)).value) == 11
  assert uint64(load(memory, MemoryAddress(0xfeff0000), AccessWidth(1)).value) == 13
  let updated = store(memory, MemoryAddress(196608), AccessWidth(1), RegisterValue(55)).value
  assert uint64(load(updated, MemoryAddress(196608), AccessWidth(1)).value) == 55
  assert uint64(load(memory, MemoryAddress(196608), AccessWidth(1)).value) == 11
  assert instruction(programOf(machine).value, CodeAddress(0)).value.opcode == 0

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Success and all temporary copies release without retaining a program/memory ownership cycle.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_initialization", 1000, before, after)
echo "PVM initialization passed"
echo "ARC_RELEASE cycles=1000 unchanged"
