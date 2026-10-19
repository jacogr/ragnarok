# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent host byte-range witnesses for natural bounds, page permissions and atomic writes.
## Checks complete byte contents, immutable aliases, input lifetimes and 1,000 ARC release cycles.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step, output]
import ../../support/arc_evidence

# Build three consecutive pages with independent address-derived bytes and configurable middle access.
proc fixture(access: PageAccess): Memory =
  var pages: seq[PageImage] = @[]
  for ordinal in 16'u32..18'u32:
    # Each byte is checked later against arithmetic independent of the copy implementation.
    var page = PageImage(index: PageIndex(ordinal), access: (if ordinal == 17: access
      else: PageAccess.ReadWrite), bytes: default(array[4096, byte]))
    for i in 0..<4096:
      # A nonzero, nonconstant pattern exposes page/offset mistakes.
      page.bytes[i] = byte((uint64(ordinal) * 4096 + uint64(i)) mod 251)
    pages.add(page)
  captureMemory(pages, PageLimit(3)).value

let original = fixture(PageAccess.ReadWrite)
for offset in [0, 1, 4095, 4096]:
  for size in [0, 1, 2, 4095, 4096, 4097, 8192]:
    # Compare aligned, unaligned and multiple-page reads with an independently calculated byte stream.
    let address = 65536'u64 + uint64(offset)
    let read = readBytes(original, MemoryAddress(address), MemoryLength(uint64(size)),
        MemoryByteLimit(uint64(size)))
    assert read.error == MachineError.None and read.value.len == size
    let observed = read.value
    for i in 0..<size:
      # Every copied byte, including both sides of page boundaries, must match its physical address.
      assert observed[i] == byte((address + uint64(i)) mod 251)
    var input = newSeq[byte](size)
    for i in 0..<size:
      # New data differs from the old pages while retaining an independently known pattern.
      input[i] = byte((i * 7 + 19) mod 256)
    let written = writeBytes(original, MemoryAddress(address), input, MemoryByteLimit(uint64(size)))
    assert written.error == MachineError.None
    let all = readBytes(written.value, MemoryAddress(65536), MemoryLength(12288), MemoryByteLimit(12288)).value
    for i in 0..<12288:
      # Bytes outside the exact requested extent remain unchanged, including untouched page suffixes.
      let expected = (if i >= offset and i - offset < size: input[i - offset]
        else: byte((65536 + i) mod 251))
      assert all[i] == expected
    if size > 0:
      # A one-short local cap rejects both reads and writes before any payload allocation.
      assert readBytes(original, MemoryAddress(address), MemoryLength(uint64(size)),
        MemoryByteLimit(uint64(size - 1))).error == MachineError.LimitExceeded
      assert writeBytes(original, MemoryAddress(address), input,
        MemoryByteLimit(uint64(size - 1))).error == MachineError.LimitExceeded

for access in [PageAccess.ReadOnly, PageAccess.Inaccessible]:
  # A late permission failure must not publish or modify the writable prefix page.
  let source = fixture(access)
  let rejected = writeBytes(source, MemoryAddress(69631), [9'u8, 8, 7], MemoryByteLimit(3))
  assert rejected.error == MachineError.Fault and uint32(rejected.faultPage) == 69632
  assert pageImage(source, PageIndex(16)).value.bytes[4095] == byte(69631 mod 251)
  let read = readBytes(source, MemoryAddress(69631), MemoryLength(3), MemoryByteLimit(3))
  assert read.error == (if access == PageAccess.ReadOnly: MachineError.None else: MachineError.Fault)

# Missing pages and explicitly inaccessible pages share the same first-failure diagnostic.
let empty = captureMemory([], PageLimit(0)).value
assert readBytes(empty, MemoryAddress(70000), MemoryLength(1), MemoryByteLimit(1)).error ==
    MachineError.Fault
assert uint32(readBytes(empty, MemoryAddress(70000), MemoryLength(1), MemoryByteLimit(
    1)).faultPage) == 69632
for address in [0'u64, 0x100000000'u64, high(uint64)]:
  # Empty natural intervals are permitted even outside the physical address domain.
  assert readBytes(empty, MemoryAddress(address), MemoryLength(0), MemoryByteLimit(0)).value.len == 0
  assert writeBytes(empty, MemoryAddress(address), [], MemoryByteLimit(0)).error ==
      MachineError.None
assert readBytes(default(Memory), MemoryAddress(0), MemoryLength(0), MemoryByteLimit(0)).error ==
    MachineError.InvalidOwner
assert writeBytes(default(Memory), MemoryAddress(0), [], MemoryByteLimit(0)).error ==
    MachineError.InvalidOwner
for address in [0x100000000'u64, high(uint64)]:
  # Nonempty high-bit addresses cannot alias a physical page by truncation.
  assert readBytes(original, MemoryAddress(address), MemoryLength(1), MemoryByteLimit(1)).error ==
      MachineError.InvalidRange
  assert writeBytes(original, MemoryAddress(address), [1'u8], MemoryByteLimit(1)).error ==
      MachineError.InvalidRange
assert readBytes(original, MemoryAddress(65536), MemoryLength(high(uint64)), MemoryByteLimit(high(
    uint64))).error == MachineError.InvalidRange
assert readBytes(original, MemoryAddress(65536), MemoryLength(10), MemoryByteLimit(0)).error ==
    MachineError.LimitExceeded

# Host access consults actual page permissions, without scalar low-address panic or cyclic wrapping.
var low = PageImage(index: PageIndex(0), access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))
low.bytes[0] = 51
var top = PageImage(index: PageIndex(0xfffff), access: PageAccess.ReadWrite, bytes: default(array[
    4096, byte]))
top.bytes[4095] = 99
let edge = captureMemory([low, top], PageLimit(2)).value
assert readBytes(edge, MemoryAddress(0), MemoryLength(1), MemoryByteLimit(1)).value == @[51'u8]
assert readBytes(edge, MemoryAddress(0xffffffff'u64), MemoryLength(1), MemoryByteLimit(1)).value == @[99'u8]
assert writeBytes(edge, MemoryAddress(0), [7'u8], MemoryByteLimit(1)).error == MachineError.None
assert writeBytes(edge, MemoryAddress(0xffffffff'u64), [7'u8], MemoryByteLimit(1)).error ==
    MachineError.None
assert readBytes(edge, MemoryAddress(0xffffffff'u64), MemoryLength(2), MemoryByteLimit(2)).error ==
    MachineError.InvalidRange
assert writeBytes(edge, MemoryAddress(0xffffffff'u64), [7'u8, 8], MemoryByteLimit(2)).error ==
    MachineError.InvalidRange

# A trusted handler uses the byte-range writer, then normal execution returns those bytes to the caller.
proc reply(input: var seq[byte], stopped: StepOutcome): HostResponse {.raises: [].} =
  let cpu = machineInfo(stopped.machine).value
  HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: cpu.registers,
    memory: writeBytes(memoryOf(stopped.machine).value, MemoryAddress(69631), input,
      MemoryByteLimit(3)).value)

let code = decodeProgram([0'u8, 0, 4, 10, 2, 50, 0, 5], CodeAddress(0),
  ProgramByteLimit(8), JumpCountLimit(0)).value
var cpu = MachineInfo(pc: CodeAddress(0), gas: MachineGas(0), blockCharged: true,
  registers: default(RegisterFile))
cpu.registers[0] = RegisterValue(0xffff0000'u64)
cpu.registers[7] = RegisterValue(69631)
cpu.registers[8] = RegisterValue(3)
let invocation = captureMachine(code, original, cpu).value
var supplied = @[21'u8, 22, 23]
let halted = executeWithHost(invocation, supplied, reply, ExecutionStepLimit(2), HostCallLimit(1),
  GasCycleLimit(0)).value
supplied[0] = 99
assert halted.exit == StepExit.Halt
assert captureOutput(halted, OutputByteLimit(3)).value == @[21'u8, 22, 23]
assert pageImage(original, PageIndex(16)).value.bytes[4095] == byte(69631 mod 251)

# Complete owner lifetimes exercise borrowed inputs, extracted byte copies and independent descendants.
proc cycle() =
  let memory = fixture(PageAccess.ReadWrite)
  var input = @[7'u8, 8, 9]
  let first = writeBytes(memory, MemoryAddress(69631), input, MemoryByteLimit(3)).value
  input[0] = 99
  let second = writeBytes(first, MemoryAddress(69631), input, MemoryByteLimit(3)).value
  let copied = readBytes(first, MemoryAddress(69631), MemoryLength(3), MemoryByteLimit(3))
  var bytes = copied.value
  bytes[0] = 11
  assert copied.value == @[7'u8, 8, 9]
  assert readBytes(first, MemoryAddress(69631), MemoryLength(3), MemoryByteLimit(3)).value == @[
      7'u8, 8, 9]
  assert readBytes(second, MemoryAddress(69631), MemoryLength(3), MemoryByteLimit(3)).value == @[
      99'u8, 8, 9]
  assert pageImage(memory, PageIndex(16)).value.bytes[4095] == byte(69631 mod 251)

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # No source, borrowed input or extracted mutable sequence is retained by a dead descendant.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_host_memory", 1000, before, after)
echo "PVM host memory passed"
echo "ARC_RELEASE cycles=1000 unchanged"
