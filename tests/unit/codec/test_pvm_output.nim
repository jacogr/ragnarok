# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native witnesses for halted PVM return buffers and natural nonwrapping address ranges.
## Tests initializer/execution composition, page permissions, full preflight, local limits and ARC.

# @@Verification={"arc": "pvm_output_arc_release"}

import std/assertions
import std/syncio
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/initialize as pvm_initialize
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/output as pvm_output
import ../../support/testing_arc_evidence

# An original minimal standard envelope runs jump_ind through the initialized return-address register.
proc initialized(arguments: openArray[byte]): Machine =
  initializeMachine([0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0,
    0, 0, 2, 50, 0, 1], arguments, CodeAddress(0), MachineGas(100),
    InitializationLimits(envelope: InitializationByteLimit(21), program: ProgramByteLimit(6),
      jumps: JumpCountLimit(0), pages: PageLimit(4))).value

# Trusted tests alter only return registers; execute produces the actual Halt outcome under test.
proc halted(memory: Memory, pointer, length: uint64): StepOutcome =
  let original = initialized([])
  var info = machineInfo(original).value
  info.registers[7] = RegisterValue(pointer)
  info.registers[8] = RegisterValue(length)
  let source = captureMachine(programOf(original).value, memory, info).value
  execute(source, ExecutionStepLimit(1), GasCycleLimit(100)).value

# Construct distinguishable pages with explicit access, including inaccessible pages retaining bytes.
proc image(index: uint32, access: PageAccess): PageImage =
  result = PageImage(index: PageIndex(index), access: access, bytes: default(array[4096, byte]))
  for i in 0..<4096:
    # The expected byte stream is independent of the extraction implementation's chunking.
    result.bytes[i] = byte((uint64(index) * 4096 + uint64(i)) mod 251)

# Every unreadable range returns an empty success, even when its claimed length exceeds local policy.
proc empty(memory: Memory, pointer, length: uint64) =
  let result = captureOutput(halted(memory, pointer, length), OutputByteLimit(0))
  assert result.error == OutputError.None
  assert result.value.len == 0

let pages = captureMemory([image(16, PageAccess.ReadOnly), image(17, PageAccess.ReadWrite),
  image(18, PageAccess.ReadOnly)], PageLimit(3)).value
for start in [65536'u64, 65537, 69631, 69632, 73727]:
  for length in [1'u64, 2, 4095, 4096, 4097]:
    # All selected intervals fit within these three consecutive mapped pages.
    if start + length <= 77824:
      let outcome = halted(pages, start, length)
      let captured = captureOutput(outcome, OutputByteLimit(length))
      assert captured.error == OutputError.None
      let bytes = captured.value
      assert bytes.len == int(length)
      for i in 0..<bytes.len:
        # Verify every byte across unaligned boundaries and permission changes.
        assert bytes[i] == byte((start + uint64(i)) mod 251)
      assert captureOutput(outcome, OutputByteLimit(length - 1)).error == OutputError.LimitExceeded

# Empty intervals do not dereference the pointer, even outside the guest address domain.
for pointer in [0'u64, 65535, 77824, 0xffffffff'u64, 0x100000000'u64, high(uint64)]:
  empty(pages, pointer, 0)
# Nonempty invalid intervals never wrap into low memory, nor truncate length or pointer to 32 bits.
for pointer in [0'u64, 65535, 77824, 0x100000000'u64, high(uint64)]:
  empty(pages, pointer, 1)
empty(pages, 65536, high(uint64))
empty(pages, high(uint64), high(uint64))
empty(pages, 65536, 12289)
empty(pages, 65535, 2)

# Return readability follows page access, not the separate scalar-instruction low-address panic rule.
let lowPage = captureMemory([image(0, PageAccess.ReadOnly)], PageLimit(1)).value
let lowBytes = captureOutput(halted(lowPage, 0, 2), OutputByteLimit(2)).value
assert lowBytes == @[0'u8, 1]

let lastPage = captureMemory([image(0xfffff, PageAccess.ReadOnly)], PageLimit(1)).value
let finalByte = captureOutput(halted(lastPage, 0xffffffff'u64, 1), OutputByteLimit(1)).value
assert finalByte.len == 1 and finalByte[0] == byte(0xffffffff'u64 mod 251)
empty(lastPage, 0xffffffff'u64, 2)
empty(lastPage, 0xfffff000'u64, 4097)
assert captureOutput(halted(lastPage, 0xfffff000'u64, 4096), OutputByteLimit(4096)).value.len == 4096

# A hole in the middle invalidates the whole interval, even when both endpoints are readable.
let hole = captureMemory([image(16, PageAccess.ReadWrite), image(18, PageAccess.ReadOnly)],
    PageLimit(2)).value
empty(hole, 65536, 12288)
let denied = captureMemory([image(16, PageAccess.ReadOnly), image(17, PageAccess.Inaccessible),
  image(18, PageAccess.ReadWrite)], PageLimit(3)).value
empty(denied, 65536, 12288)
empty(denied, 69632, 1)

# Original argument bytes can be returned unchanged through real standard initialization and execution.
proc cycle() =
  var args = newSeq[byte](8193)
  for i in 0..<args.len:
    # Read-only input spans three pages including one byte in the final page.
    args[i] = byte(i mod 251)
  let source = initialized(args)
  let outcome = execute(source, ExecutionStepLimit(1), GasCycleLimit(100)).value
  assert outcome.exit == StepExit.Halt
  let captured = captureOutput(outcome, OutputByteLimit(8193))
  assert captured.error == OutputError.None
  var first = captured.value
  assert first == args
  first[0] = 255
  args[1] = 254
  let second = captured.value
  assert second[0] == 0 and second[1] == 1
  assert uint64(load(memoryOf(outcome.machine).value, MemoryAddress(0xfeff0000), AccessWidth(
      1)).value) == 0
  assert machineInfo(source).value.blockCharged == false
  assert uint64(machineInfo(source).value.gas) == 100

cycle()
# Public machine-handle replacement is validated before even the empty-interval path.
var broken = halted(pages, 0, 0)
broken.machine = default(Machine)
assert captureOutput(broken, OutputByteLimit(0)).error == OutputError.InvalidMachine
let unfinished = default(StepOutcome)
assert captureOutput(unfinished, OutputByteLimit(0)).error == OutputError.NotHalted

# Generate each other executable exit with ordinary instruction bytes; none is a successful return.
for code in [@[0'u8], @[10'u8], @[52'u8, 7, 0, 0, 2], @[2'u8]]:
  var raw = @[0'u8, 0, byte(code.len + 1)]
  for value in code:
    # Append a trap terminator after host/load/fallthrough; each partition has an explicit opcode bit.
    raw.add(value)
  raw.add(0)
  raw.add(byte(1 or (1 shl code.len)))
  let program = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(16), JumpCountLimit(0)).value
  # Prepaid blocks isolate exit classification from the independent host-call gas simulation.
  let source = captureMachine(program, pages, MachineInfo(pc: CodeAddress(0), gas: MachineGas(100),
    blockCharged: true, registers: default(RegisterFile))).value
  let evaluated = (if code[0] == 2: stepOnce(source, GasCycleLimit(100))
    else: execute(source, ExecutionStepLimit(3), GasCycleLimit(100)))
  assert evaluated.error == StepError.None, "nonhalt opcode " & $code[0] & " error " &
      $evaluated.error
  let outcome = evaluated.value
  let expected = (if code[0] == 0: StepExit.Panic elif code[0] == 10: StepExit.Host
    elif code[0] == 52: StepExit.Fault else: StepExit.Continued)
  assert outcome.exit == expected
  assert captureOutput(outcome, OutputByteLimit(100)).error == OutputError.NotHalted
let starved = captureMachine(programOf(initialized([])).value, pages, MachineInfo(pc: CodeAddress(0),
  gas: MachineGas(0), blockCharged: false, registers: default(RegisterFile))).value
assert captureOutput(execute(starved, ExecutionStepLimit(1), GasCycleLimit(100)).value,
  OutputByteLimit(0)).error == OutputError.NotHalted

let before = getOccupiedMem()
for iteration in 0..<1000:
  # Repeated copied outputs and complete machine lifetimes retain no cycle or mutable alias.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_output", 1000, before, after)
echo "PVM output passed"
echo "ARC_RELEASE cycles=1000 unchanged"
