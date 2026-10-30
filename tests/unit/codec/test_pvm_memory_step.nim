# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native witnesses for all charged PVM load/store instructions and memory exception ordering.
## Exercises stepMemory, fault-page selection, immutable snapshots and repaired-fault retries.

# @@Verification={"arc": "pvm_memory_step_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
import ../../support/arc_evidence

# Literal instruction-table inventory; widths and signedness are independent test expectations.
const ops = [30'u8, 31, 32, 33, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62,
  70, 71, 72, 73, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130]
const widths = [1, 2, 4, 8, 1, 1, 2, 2, 4, 4, 8, 1, 2, 4, 8,
  1, 2, 4, 8, 1, 2, 4, 8, 1, 1, 2, 2, 4, 4, 8]
const signedOps = {53'u8, 55'u8, 57'u8, 125'u8, 127'u8, 129'u8}

# Serialize four little-endian immediate bytes directly, without using the production operand decoder.
proc immediate(bytes: var seq[byte], value: uint64) =
  # Every test immediate has a fixed explicit width; sign extension is tested after decoding.
  for i in 0..<4: bytes.add(byte((value shr (i * 8)) and 255))

# Encode one memory instruction and trap with explicit operand bytes and opcode-mask positions.
proc owner(op: byte, address, offset: uint64, alias: bool): Program =
  var code = @[op]
  if op <= 33:
    # Two immediates: absolute address X and a negative signed-four-byte store value Y.
    code.add(4)
    immediate(code, address)
    immediate(code, 0x89abcdef'u64)
  elif op >= 70 and op <= 73:
    # One saturated base register and two four-byte immediates, offset X and data Y.
    code.add(79)
    immediate(code, offset)
    immediate(code, 0x89abcdef'u64)
  else:
    # Absolute forms write/read saturated A; indirect forms select B=1 or alias B=A=12.
    let descriptor = (if op < 120: 15'u8 elif alias: 255'u8 else: 31'u8)
    code.add(descriptor)
    immediate(code, (if op < 120: address else: offset))
  let stop = code.len
  code.add(0)
  var bytes = @[0'u8, 0, byte(code.len)]
  # Copy the independently encoded instruction stream into the short blob.
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len + 7) div 8)
  mask[0] = 1
  mask[stop div 8] = mask[stop div 8] or (1'u8 shl (stop mod 8))
  # Only the memory opcode and trailing trap are marked as instructions.
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value

# Build a copied page with a uniform byte pattern, so load expectations need no production reads.
proc page(index: uint32, access: PageAccess, value: byte): PageImage =
  result = PageImage(index: PageIndex(index), access: access, bytes: default(array[4096, byte]))
  # Fill even inaccessible page images to detect accidental reads or writes through permissions.
  for i in 0..<4096: result.bytes[i] = value

# Compare all copied CPU fields; a failure cannot hide a clobbered register or charged flag.
proc same(actual, expected: MachineInfo) =
  assert uint64(actual.pc) == uint64(expected.pc)
  assert uint64(actual.gas) == uint64(expected.gas)
  assert actual.blockCharged == expected.blockCharged
  # Include every unrelated register, not only the load destination.
  for i in 0..<13: assert uint64(actual.registers[i]) == uint64(expected.registers[i])

# Check exact page images and permissions independently of scalar permission-aware reads.
proc samePages(memory: Memory, expected: openArray[PageImage]) =
  # Inspect copied images even when permissions intentionally prohibit guest access.
  for wanted in expected:
    let actual = pageImage(memory, wanted.index).value
    assert actual.access == wanted.access
    assert actual.bytes == wanted.bytes

# Run a witness with prepaid, exact and insufficient gas, comparing complete retained snapshots.
# Expected exceptions are supplied by the caller's boundary/permission matrix.
proc witness(op: byte, width: int, address, base, offset: uint64, alias: bool,
    pages: openArray[PageImage], exit: StepExit, fault: uint32) =
  let program = owner(op, address, offset, alias)
  let decoded = instruction(program, CodeAddress(0))
  assert decoded.error == ProgramError.None
  let operands = instructionMemoryOperands(decoded)
  assert int(operands.width) == width
  assert operands.isLoad == (op in {52'u8..58'u8, 124'u8..130'u8})
  assert operands.isSigned == (op in signedOps)
  assert operands.usesImmediate == (op in {30'u8..33'u8, 70'u8..73'u8})
  let expectedBase = (if op in {70'u8..73'u8}: MemoryBase.A
    elif op in {120'u8..130'u8}: MemoryBase.B else: MemoryBase.None)
  assert operands.base == expectedBase
  let memory = captureMemory(pages, PageLimit(4)).value
  var regs = default(RegisterFile)
  # Sentinels make accidental writes to non-destination registers observable.
  for i in 0..<13: regs[i] = RegisterValue(uint64(i) * 1234567)
  regs[12] = RegisterValue(0x123456789abcdef0'u64)
  regs[1] = RegisterValue(base)
  if op in {70'u8..73'u8} or (op >= 120 and alias):
    # These encodings use saturated A as base; aliased stores must also use its original data.
    regs[12] = RegisterValue(base)
  let price = uint64(blockGas(program, CodeAddress(0), GasCycleLimit(1000)).value)
  assert price > 0
  # Prepaid zero gas exercises retry semantics; exact gas proves the debit survives faults/panics.
  for mode in 0..<3:
    let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(if mode == 0: 0'u64
      elif mode == 1: price else: price - 1), blockCharged: mode == 0, registers: regs)
    let source = captureMachine(program, memory, initial).value
    let answer = stepMemory(source, GasCycleLimit(if mode == 0: 0'u64 else: 1000'u64))
    let executed = execute(source, ExecutionStepLimit(2),
      GasCycleLimit(if mode == 0: 0'u64 else: 1000'u64))
    assert executed.error == answer.error
    same(machineInfo(source).value, initial)
    samePages(memoryOf(source).value, pages)
    if mode == 2:
      # Gas refusal precedes even protected or inaccessible memory access.
      assert answer.error == StepError.None and answer.value.exit == StepExit.OutOfGas
      same(machineInfo(answer.value.machine).value, initial)
      samePages(memoryOf(answer.value.machine).value, pages)
      assert executed.value.exit == StepExit.OutOfGas
      same(machineInfo(executed.value.machine).value, initial)
      samePages(memoryOf(executed.value.machine).value, pages)
      continue
    assert answer.error == StepError.None and answer.value.exit == exit
    var expected = initial
    expected.gas = MachineGas(0)
    expected.blockCharged = true
    var expectedPages: seq[PageImage] = @[]
    # Copy test images; later expected writes cannot mutate the source fixtures.
    for image in pages: expectedPages.add(image)
    if exit == StepExit.Continued:
      # Memory instructions advance to the trailing trap and retain the charged block.
      expected.pc = CodeAddress(codeLength(program).value - 1)
      let loading = op in {52'u8..58'u8, 124'u8..130'u8}
      if loading:
        # Accumulate bytes from the independent page images, not from production load().
        var value = 0'u64
        # Each expected little-endian byte is derived from the supplied page image.
        for i in 0..<width:
          let physical = (address + uint64(i)) and 0xffffffff'u64
          # Locate the expected byte in the independent input pages.
          for image in pages:
            # Every successful expected read is backed by one supplied page.
            if uint64(uint32(image.index)) == physical div 4096:
              value += uint64(image.bytes[int(physical mod 4096)]) shl (i * 8)
        if op in signedOps and value >= (1'u64 shl (width * 8 - 1)):
          # Mathematical subtraction modulo 2^64 gives the signed register representation.
          value = value - (1'u64 shl (width * 8))
        expected.registers[12] = RegisterValue(value)
      else:
        # Immediate stores sign-extend their four-byte Y; register stores retain all original bits.
        let value = (if op <= 33 or op in {70'u8..73'u8}: 0xffffffff89abcdef'u64
          else: uint64(regs[12]))
        # Each expected little-endian byte is derived from the supplied page image.
        for i in 0..<width:
          let physical = (address + uint64(i)) and 0xffffffff'u64
          # Update only the copied reference page containing this byte.
          for j in 0..<expectedPages.len:
            # Apply the low-byte write only to the addressed location of the copied reference page.
            if uint64(uint32(expectedPages[j].index)) == physical div 4096:
              expectedPages[j].bytes[int(physical mod 4096)] = byte((value shr (i * 8)) and 255)
    elif exit == StepExit.Fault:
      # Physical aligned addresses are not page ordinals and are available only on Fault.
      assert uint32(answer.value.faultPage) == fault
    else:
      # Protected-memory panic preserves the original PC and every register, unlike trap.
      assert exit == StepExit.Panic
    same(machineInfo(answer.value.machine).value, expected)
    samePages(memoryOf(answer.value.machine).value, expectedPages)
    # A successful memory instruction reaches the following trap; exceptions stop at the access itself.
    let expectedExit = (if exit == StepExit.Continued: StepExit.Panic else: exit)
    assert executed.value.exit == expectedExit
    var executedInfo = expected
    if expectedExit == StepExit.Panic:
      # Recursive Psi normalizes a final panic PC regardless of its memory/trap origin.
      executedInfo.pc = CodeAddress(0)
    if expectedExit == StepExit.Fault:
      # Normalization must preserve the fault page rather than losing exit metadata.
      assert uint32(executed.value.faultPage) == fault
    same(machineInfo(executed.value.machine).value, executedInfo)
    samePages(memoryOf(executed.value.machine).value, expectedPages)

# Cross all memory opcodes, permission pairs, sign patterns and near-page-boundary addresses.
for row in 0..<ops.len:
  let op = ops[row]
  let width = widths[row]
  let loading = op in {52'u8..58'u8, 124'u8..130'u8}
  for first in [PageAccess.Inaccessible, PageAccess.ReadOnly, PageAccess.ReadWrite]:
    # A separate permission for the second page catches partial cross-page stores.
    for second in [PageAccess.Inaccessible, PageAccess.ReadOnly, PageAccess.ReadWrite]:
      # Include an ordinary address and crossings with different prefix lengths.
      for offset in [0'u64, 4093'u64, 4095'u64]:
        # Positive and negative load patterns test every signed width at the destination register.
        for pattern in [127'u8, 128'u8]:
          let address = 65536 + offset
          let firstOk = first == PageAccess.ReadWrite or (loading and first == PageAccess.ReadOnly)
          let secondOk = second == PageAccess.ReadWrite or (loading and second ==
              PageAccess.ReadOnly)
          let crossed = offset + uint64(width) > 4096
          let exit = (if not firstOk or (crossed and not secondOk): StepExit.Fault
            else: StepExit.Continued)
          let fault = (if not loading and crossed and first == PageAccess.ReadOnly and
              second == PageAccess.Inaccessible: 69632'u32
            elif not firstOk: 65536'u32 else: 69632'u32)
          witness(op, width, address, address + 1, high(uint64), false,
            [page(16, first, pattern), page(17, second, pattern)], exit, fault)
  # Distinct neighboring bytes catch wrong effective addresses, byte order and cross-page load assembly.
  var variedFirst = page(16, PageAccess.ReadWrite, 0)
  var variedSecond = page(17, PageAccess.ReadWrite, 0)
  for i in 0..<4096:
    # Different page seeds make an accidentally repeated first-page byte observable too.
    variedFirst.bytes[i] = byte((i * 37 + 11) and 255)
    variedSecond.bytes[i] = byte((i * 23 + 91) and 255)
  witness(op, width, 65573, 65536, 37, false,
    [variedFirst, variedSecond], StepExit.Continued, 0)
  witness(op, width, 69629, 69630, high(uint64), false,
    [variedFirst, variedSecond], StepExit.Continued, 0)
  # Aliased indirect address/value/destination roles use old registers, including a 64-bit sum overflow.
  witness(op, width, 65536, high(uint64), 65537, true,
    [page(16, PageAccess.ReadWrite, 128)], StepExit.Continued, 0)
  # Low memory protection cannot be bypassed by supplying accessible low pages.
  witness(op, width, 65535, 65536, high(uint64), false,
    [page(15, PageAccess.ReadWrite, 127), page(16, PageAccess.ReadWrite, 128)], StepExit.Panic, 0)
  # An absent page faults just like an explicitly inaccessible page.
  witness(op, width, 65536, 65537, high(uint64), false, [], StepExit.Fault, 65536)
  # PolkaVM exclusive-end overflow applies even to width1 atMAX32 and precedes read-only checks.
  witness(op, width, 0xffffffff'u64, 0x100000000'u64, high(uint64), false,
    [], StepExit.Fault, 0xfffff000'u32)
  for access in [PageAccess.ReadOnly, PageAccess.ReadWrite]:
    # Both kinds of present final page trap, including a wrapping store to a read-only page.
    witness(op, width, 0xffffffff'u64, 0x100000000'u64, high(uint64), false,
      [page(0xfffff, access, 128)], StepExit.Panic, 0)

# A fault preserves the already-charged block; repairing memory retries without another gas simulation.
proc retryCycle() =
  let program = owner(62, 69629, 0, false)
  let first = page(16, PageAccess.ReadWrite, 128)
  let second = page(17, PageAccess.ReadOnly, 127)
  let memory = captureMemory([first, second], PageLimit(2)).value
  var regs = default(RegisterFile)
  regs[12] = RegisterValue(0x123456789abcdef0'u64)
  let cost = blockGas(program, CodeAddress(0), GasCycleLimit(1000)).value
  let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(
      uint64(cost)),
    blockCharged: false, registers: regs)).value
  let fault = stepMemory(source, GasCycleLimit(1000)).value
  assert fault.exit == StepExit.Fault and uint32(fault.faultPage) == 69632
  samePages(memoryOf(fault.machine).value, [first, second])
  let repeated = stepMemory(fault.machine, GasCycleLimit(0)).value
  assert repeated.exit == StepExit.Fault
  same(machineInfo(repeated.machine).value, machineInfo(fault.machine).value)
  var writable = second
  writable.access = PageAccess.ReadWrite
  let repaired = withMemory(fault.machine, withPage(memoryOf(fault.machine).value,
      writable).value).value
  let retried = stepMemory(repaired, GasCycleLimit(0)).value
  assert retried.exit == StepExit.Continued
  assert uint64(machineInfo(retried.machine).value.gas) == 0
  assert uint64(load(memoryOf(retried.machine).value, MemoryAddress(69629), AccessWidth(
      8)).value) ==
    0x123456789abcdef0'u64
  samePages(memoryOf(source).value, [first, second])
  samePages(memoryOf(fault.machine).value, [first, second])

# Rechecking the PolkaVM overflow rule after host page repair must preserve the paid block across every transition.
proc overflowRetryCycle() =
  for row in 0..<ops.len:
    # Every absolute/immediate/indirect form uses the same effective final-byte address with its own original register roles.
    let op = ops[row]
    let program = owner(op, 0xffffffff'u64, high(uint64), false)
    let memory = captureMemory([], PageLimit(1)).value
    var regs = default(RegisterFile)
    regs[1] = RegisterValue(0x100000000'u64)
    regs[12] = RegisterValue(0x123456789abcdef0'u64)
    if op in {70'u8..73'u8}:
      regs[12] = RegisterValue(0x100000000'u64) # These indirect immediate stores select saturated A as their address base.
    let cost = blockGas(program, CodeAddress(0), GasCycleLimit(1000)).value
    let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(uint64(cost)),
      blockCharged: false, registers: regs)
    let source = captureMachine(program, memory, initial).value
    let fault = stepMemory(source, GasCycleLimit(1000)).value
    assert fault.exit == StepExit.Fault and uint32(fault.faultPage) == 0xfffff000'u32
    var paid = initial
    paid.gas = MachineGas(0)
    paid.blockCharged = true
    same(machineInfo(fault.machine).value, paid)
    let repeated = stepMemory(fault.machine, GasCycleLimit(0)).value
    assert repeated.exit == StepExit.Fault and uint32(repeated.faultPage) == 0xfffff000'u32
    same(machineInfo(repeated.machine).value, paid)
    for access in [PageAccess.ReadOnly, PageAccess.ReadWrite]:
      # Presence makes PolkaVM overflow trap even for stores to the supplied read-only page.
      let image = page(0xfffff, access, 181)
      let present = withMemory(fault.machine, withPage(memory, image).value).value
      let panic = stepMemory(present, GasCycleLimit(0)).value
      assert panic.exit == StepExit.Panic
      same(machineInfo(panic.machine).value, paid)
      samePages(memoryOf(panic.machine).value, [image])
      let completed = execute(present, ExecutionStepLimit(1), GasCycleLimit(0)).value
      assert completed.exit == StepExit.Panic
      same(machineInfo(completed.machine).value, paid)
      samePages(memoryOf(completed.machine).value, [image])
      var hidden = image
      hidden.access = PageAccess.Inaccessible
      let unmapped = withMemory(panic.machine, withPage(memoryOf(panic.machine).value,
          hidden).value).value
      let again = stepMemory(unmapped, GasCycleLimit(0)).value
      assert again.exit == StepExit.Fault and uint32(again.faultPage) == 0xfffff000'u32
      same(machineInfo(again.machine).value, paid)
      samePages(memoryOf(again.machine).value, [hidden])
      samePages(memoryOf(present).value, [image])
      samePages(memoryOf(panic.machine).value, [image])
      samePages(memoryOf(unmapped).value, [hidden])
    same(machineInfo(source).value, initial)
    same(machineInfo(fault.machine).value, paid)
    assert pageImage(memoryOf(source).value, PageIndex(0xfffff)).value.access ==
        PageAccess.Inaccessible

# A repaired aliased load must still use its original base and then replace it with the loaded value.
let loadProgram = owner(130, 69631, 0, true)
let initialMemory = captureMemory([page(16, PageAccess.ReadOnly, 128)], PageLimit(2)).value
var loadRegisters = default(RegisterFile)
loadRegisters[12] = RegisterValue(69631)
let loadSource = captureMachine(loadProgram, initialMemory, MachineInfo(pc: CodeAddress(0),
  gas: MachineGas(1000), blockCharged: false, registers: loadRegisters)).value
let loadFault = stepMemory(loadSource, GasCycleLimit(1000)).value
assert loadFault.exit == StepExit.Fault and uint32(loadFault.faultPage) == 69632
assert uint64(machineInfo(loadFault.machine).value.registers[12]) == 69631
let loadRepair = withMemory(loadFault.machine,
  withPage(initialMemory, page(17, PageAccess.ReadOnly, 128)).value).value
let loadRetry = stepMemory(loadRepair, GasCycleLimit(0)).value
assert loadRetry.exit == StepExit.Continued
assert uint64(machineInfo(loadRetry.machine).value.registers[12]) == 0x8080808080808080'u64
assert uint64(machineInfo(loadRetry.machine).value.gas) == uint64(machineInfo(
    loadFault.machine).value.gas)
assert stepMemory(default(Machine), GasCycleLimit(0)).error == StepError.InvalidMachine
assert stepMemory(loadSource, GasCycleLimit(0)).error == StepError.GasCycleLimitExceeded
# Host ecalli remains explicitly outside this entry point, even when its gas could not be afforded.
let hostProgram = decodeProgram([0'u8, 0, 2, 10, 0, 3], CodeAddress(0),
  ProgramByteLimit(32), JumpCountLimit(0)).value
let host = captureMachine(hostProgram, initialMemory, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(0),
  blockCharged: false, registers: loadRegisters)).value
assert stepMemory(host, GasCycleLimit(0)).error == StepError.UnsupportedInstruction

retryCycle()
overflowRetryCycle()
let before = getOccupiedMem()
# Releasing complete source/fault/repair/store graphs must return ARC allocation to its baseline.
for iteration in 0..<1000:
  retryCycle()
  overflowRetryCycle() # Each batch covers all30 forms and both present-page permission modes.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_memory_step", 1000, before, after)
echo "PVM memory stepping passed"
echo "ARC_RELEASE cycles=1000 unchanged"
