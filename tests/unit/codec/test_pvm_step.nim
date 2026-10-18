# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native tests replay charged execution traces and check out-of-gas ordering and ARC lifetimes.
## The executable reads RAGNAROK_PVM_STEP, tests stepRegisters and records pvm_step ARC evidence.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, registers, gas, step]
import ../../support/arc_evidence

# Read independently serialized little-endian fixture integers after checking their enclosing extent.
proc word(data: string, at, width: int): uint64 =
  result = 0
  # No production decoder participates in reading expected CPU values.
  for i in 0..<width: result = result or (uint64(byte(data[at + i])) shl (8 * i))

# Compare all CPU fields explicitly; nominal values are compared only within their own domains.
proc same(actual, expected: MachineInfo) =
  assert uint64(actual.pc) == uint64(expected.pc)
  assert uint64(actual.gas) == uint64(expected.gas)
  assert actual.blockCharged == expected.blockCharged
  # A step must preserve every unrelated register, not merely the instruction destination.
  for i in 0..<13: assert uint64(actual.registers[i]) == uint64(expected.registers[i])

# Supply readable sentinel memory so every stepped snapshot can prove memory preservation.
proc memoryOwner(): Memory =
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  page.bytes[0] = 165
  let captured = captureMemory([page], PageLimit(1))
  assert captured.error == MachineError.None
  captured.value

# Capture an independently serialized short program for API boundary and ownership tests.
proc smallProgram(code: openArray[byte], mask: byte): Program =
  assert code.len < 8
  var bytes = @[0'u8, 0, byte(code.len)]
  # Caller supplies explicit opcode bits, including unmarked bytes equal to termination opcodes.
  for value in code: bytes.add(value)
  bytes.add(mask)
  let captured = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0))
  assert captured.error == ProgramError.None
  captured.value

var data = ""
# Missing evidence is a failing setup, not an implicitly skipped execution corpus.
try:
  data = readFile(getEnv("RAGNAROK_PVM_STEP"))
except:
  # I/O failures must propagate as a nonzero native test status.
  quit 2
assert data.len >= 12 and data[0..7] == "PVMSTEP1"
let count = int(word(data, 8, 4))
assert count == 186
var cursor = 12
var seen = default(array[256, bool])
let memory = memoryOwner()
# Replay each trace at exact gas, surplus gas and zero prepaid gas.
for row in 0..<count:
  assert data.len - cursor >= 132
  let length = int(word(data, cursor, 4))
  let entry = word(data, cursor + 4, 4)
  let price = word(data, cursor + 8, 8)
  let cycles = word(data, cursor + 16, 8)
  var initial = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(price), blockCharged: false,
    registers: default(RegisterFile))
  # Copy all initial registers from the independently generated trace.
  for i in 0..<13: initial.registers[i] = RegisterValue(word(data, cursor + 24 + i * 8, 8))
  let steps = int(word(data, cursor + 128, 4))
  cursor += 132
  assert length <= data.len - cursor
  var bytes = newSeq[byte](length)
  # The native program decoder receives the frozen encoding, not a synthesized production output.
  for i in 0..<length: bytes[i] = byte(data[cursor + i])
  cursor += length
  assert steps > 0 and steps <= (data.len - cursor) div 108
  let owner = decodeProgram(bytes, CodeAddress(entry), ProgramByteLimit(uint64(length)),
    JumpCountLimit(0))
  assert owner.error == ProgramError.None
  assert price > 0
  var insufficient = initial
  insufficient.gas = MachineGas(price - 1)
  let source = captureMachine(owner.value, memory, insufficient).value
  let exhausted = stepRegisters(source, GasCycleLimit(cycles))
  assert exhausted.error == StepError.None and exhausted.value.exit == StepExit.OutOfGas
  same(machineInfo(exhausted.value.machine).value, insufficient)
  same(machineInfo(source).value, insufficient)
  assert uint64(load(memoryOf(exhausted.value.machine).value, MemoryAddress(65536),
    AccessWidth(1)).value) == 165
  # Guest gas cannot substitute for the independent local simulation work budget.
  let limited = captureMachine(owner.value, memory, initial).value
  assert stepRegisters(limited, GasCycleLimit(cycles - 1)).error == StepError.GasCycleLimitExceeded
  same(machineInfo(limited).value, initial)
  for mode in 0..<3:
    # Prepaid blocks bypass both cost simulation and subtraction, even with no remaining gas.
    var expected = initial
    expected.gas = MachineGas(if mode == 0: price elif mode == 1: price + 17 else: 0)
    expected.blockCharged = mode == 2
    var current = captureMachine(owner.value, memory, expected).value
    for index in 0..<steps:
      # Each instruction must advance by its own decoded skip and preserve the prior snapshot.
      let prior = current
      let priorInfo = machineInfo(prior).value
      let decoded = instruction(programOf(prior).value, priorInfo.pc).value
      seen[int(decoded.opcode)] = true
      let advanced = stepRegisters(current, GasCycleLimit(if index == 0 and mode !=
          2: cycles else: 0))
      assert advanced.error == StepError.None and advanced.value.exit == StepExit.Continued
      current = advanced.value.machine
      expected.pc = CodeAddress(word(data, cursor + index * 108, 4))
      expected.gas = MachineGas(if mode == 1: 17 else: 0)
      expected.blockCharged = true
      # Expected register arrays come from the independent mathematical oracle.
      for i in 0..<13:
        expected.registers[i] = RegisterValue(word(data, cursor + index * 108 + 4 + i * 8, 8))
      same(machineInfo(current).value, expected)
      same(machineInfo(prior).value, priorInfo)
      assert uint64(load(memoryOf(current).value, MemoryAddress(65536), AccessWidth(1)).value) == 165
    # Trap is deliberately outside this bounded executor, never a fabricated terminal outcome.
    assert stepRegisters(current, GasCycleLimit(0)).error == StepError.UnsupportedInstruction
  cursor += steps * 108
assert cursor == data.len
var covered = 0
# Coverage is measured from executed instructions, including all saturated/aliased encodings.
for op in 0..<256:
  if seen[op]: inc covered
assert covered == 85
let uninitialized = default(StepResult)
assert uninitialized.error == StepError.Uninitialized
assert stepRegisters(default(Machine), GasCycleLimit(100)).error == StepError.InvalidMachine
assert programOf(default(Machine)).error == MachineError.InvalidOwner

# Every unsupported valid opcode must stay a local error, irrespective of gas or charged state.
for op in 0..255:
  if validOpcode(byte(op)) and not registerOnlyOpcode(byte(op)):
    let owner = smallProgram([byte(op), 0], 3)
    for prepaid in [false, true]:
      # Even zero gas cannot turn an unsupported operation into a claimed guest evaluation.
      let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(0), blockCharged: prepaid,
        registers: default(RegisterFile))
      let source = captureMachine(owner, memory, info).value
      assert stepRegisters(source, GasCycleLimit(0)).error == StepError.UnsupportedInstruction
      same(machineInfo(source).value, info)

# Gas scanning includes a later branch's specification gate before committing an earlier register write.
let gated = smallProgram([51'u8, 170, 0, 254, 255, 255, 255], 3)
let gatedInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), blockCharged: false,
  registers: default(RegisterFile))
let gatedMachine = captureMachine(gated, memory, gatedInfo).value
assert stepRegisters(gatedMachine, GasCycleLimit(1000)).error == StepError.NegativeBranchTarget
same(machineInfo(gatedMachine).value, gatedInfo)
# A trusted prepaid snapshot follows the GP charged-flag rule even when recomputation would hit the gate.
var prepaidInfo = gatedInfo
prepaidInfo.blockCharged = true
prepaidInfo.gas = MachineGas(0)
let prepaid = captureMachine(gated, memory, prepaidInfo).value
let resumed = stepRegisters(prepaid, GasCycleLimit(0))
assert resumed.error == StepError.None and resumed.value.exit == StepExit.Continued
assert uint64(machineInfo(resumed.value.machine).value.pc) == 1

# Boundary lookup must ignore terminator-valued operand bytes and reject unmarked/out-of-range PCs.
let boundaries = smallProgram([0'u8, 51, 0, 100, 0, 0], 43)
assert uint64(containingBlockStart(boundaries, CodeAddress(3)).value) == 1
assert containingBlockStart(boundaries, CodeAddress(2)).error == ProgramError.InvalidInstruction
assert containingBlockStart(boundaries, CodeAddress(high(uint64))).error ==
    ProgramError.InvalidInstruction
assert containingBlockStart(default(Program), CodeAddress(0)).error == ProgramError.InvalidOwner

# Release a complete program/memory/source/step graph after proving copied child-state isolation.
proc releaseCycle() =
  let owner = smallProgram([51'u8, 0, 100, 0, 0], 21)
  let memory = memoryOwner()
  let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(high(uint64)), blockCharged: false,
    registers: default(RegisterFile))
  let source = captureMachine(owner, memory, info).value
  let first = stepRegisters(source, GasCycleLimit(100)).value.machine
  let second = stepRegisters(first, GasCycleLimit(0)).value.machine
  let changed = withRegister(second, RegisterIndex(0), RegisterValue(99)).value
  assert uint64(machineInfo(changed).value.registers[0]) == 99
  assert uint64(machineInfo(second).value.registers[0]) == 0
  assert uint64(machineInfo(source).value.gas) == high(uint64)
  assert uint64(machineInfo(first).value.gas) == high(uint64) - 2

releaseCycle()
let before = getOccupiedMem()
# Repeated complete owner lifetimes detect retained cycles and accidental result/source back-references.
for iteration in 0..<1000: releaseCycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_step", 1000, before, after)
echo "PVM register stepping passed"
echo "ARC_RELEASE cycles=1000 unchanged"
