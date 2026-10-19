# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native host-call and bounded recursive-Psi execution witnesses.
## Checks stepOnce/execute PC rules, suspension/retry, private work limits and ARC release evidence.

# @@Verification={"arc": "pvm_execution_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step]
import ../../support/arc_evidence

# Encode original short instruction partitions with no dynamic table; operands are never marked as code.
proc owner(parts: openArray[seq[byte]]): Program =
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  # Independent explicit boundaries avoid using the production decoder to generate expected input.
  for part in parts:
    starts.add(code.len)
    for value in part:
      # Nimony's byte append keeps the helper independent of unavailable bulk sequence overloads.
      code.add(value)
  assert code.len < 128
  var bytes = @[0'u8, 0, byte(code.len)]
  # The short canonical length fits one natural-number byte.
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len + 7) div 8)
  # Explicit starts determine opcode bits, including when operands contain trap-valued zeroes.
  for at in starts: mask[at div 8] = mask[at div 8] or (1'u8 shl (at mod 8))
  for value in mask:
    # Append the complete bitmap after all instruction bytes.
    bytes.add(value)
  decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0)).value

# Supply one immutable page and sentinel registers for CPU/memory preservation checks.
proc memoryOwner(access: PageAccess): Memory =
  captureMemory([PageImage(index: PageIndex(16), access: access,
    bytes: default(array[4096, byte]))], PageLimit(1)).value

# Capture an executable source using explicit copied register state and caller-controlled paid status.
proc source(program: Program, memory: Memory, registers: RegisterFile, pc, gas: uint64,
    charged: bool): Machine =
  captureMachine(program, memory, MachineInfo(pc: CodeAddress(pc), gas: MachineGas(gas),
    blockCharged: charged, registers: registers)).value

# Compare every CPU field; successful and failed evaluations must not clobber unrelated registers.
proc same(actual, expected: MachineInfo) =
  assert uint64(actual.pc) == uint64(expected.pc)
  assert uint64(actual.gas) == uint64(expected.gas)
  assert actual.blockCharged == expected.blockCharged
  for i in 0..<13:
    # All thirteen values participate even when the witness only intentionally changes one.
    assert uint64(actual.registers[i]) == uint64(expected.registers[i])

let memory = memoryOwner(PageAccess.ReadWrite)
var registers = default(RegisterFile)
# Distinguishable untouched values expose accidental host-side effects.
for i in 0..<13: registers[i] = RegisterValue(uint64(i) * 1234567)

# Literal expected host identifiers cover every compact width, sign extension and ignored extra operands.
let arguments = [newSeq[byte](0), @[127'u8], @[128'u8], @[0'u8, 128], @[0'u8, 0, 128],
  @[120'u8, 86, 52, 18], @[0'u8, 0, 0, 128], @[255'u8, 255, 255, 255, 99], newSeq[byte](24)]
let identifiers = [0'u64, 127, 0xffffffffffffff80'u64, 0xffffffffffff8000'u64,
  0xffffffffff800000'u64, 0x12345678, 0xffffffff80000000'u64, high(uint64), 0]
for row in 0..<arguments.len:
  var call = @[10'u8]
  # The assembler helper receives these exact original bytes, including nonsemantic trailing data.
  for value in arguments[row]: call.add(value)
  let program = owner([@[1'u8], call, @[0'u8]])
  let price = uint64(blockGas(program, CodeAddress(1), GasCycleLimit(1000)).value)
  for prepaid in [true, false]:
    # An uncharged call pays its entire block; a prepaid call works at zero gas and zero simulation limit.
    let input = source(program, memory, registers, 1, (if prepaid: 0'u64 else: price), prepaid)
    let limit = GasCycleLimit(if prepaid: 0'u64 else: 1000'u64)
    let once = stepOnce(input, limit).value
    let run = execute(input, ExecutionStepLimit(1), limit).value
    assert once.exit == StepExit.Host and run.exit == StepExit.Host
    assert uint64(once.hostCall) == identifiers[row] and uint64(run.hostCall) == identifiers[row]
    var expected = machineInfo(input).value
    expected.gas = MachineGas(0)
    expected.blockCharged = true
    same(machineInfo(run.machine).value, expected)
    expected.pc = CodeAddress(1 + uint64(call.len))
    same(machineInfo(once.machine).value, expected)
    assert pageImage(memoryOf(run.machine).value, PageIndex(16)).value.bytes ==
      pageImage(memory, PageIndex(16)).value.bytes
    assert uint64(machineInfo(input).value.gas) == (if prepaid: 0'u64 else: price)
    assert stepMemory(input, limit).error == StepError.UnsupportedInstruction
  # Underfunded host suspension must not expose a host identifier or debit the original state.
  let low = source(program, memory, registers, 1, price - 1, false)
  let stopped = execute(low, ExecutionStepLimit(1), GasCycleLimit(1000)).value
  assert stopped.exit == StepExit.OutOfGas
  same(machineInfo(stopped.machine).value, machineInfo(low).value)

# Trap, invalid jump and load-and-jump halt normalize only at the recursive boundary, retaining mutations.
let trapProgram = owner([@[1'u8], @[0'u8, 99]])
let trapSource = source(trapProgram, memory, registers, 1, 0, true)
assert uint64(machineInfo(stepOnce(trapSource, GasCycleLimit(0)).value.machine).value.pc) == 3
let trap = execute(trapSource, ExecutionStepLimit(1), GasCycleLimit(0)).value
assert trap.exit == StepExit.Panic and uint64(machineInfo(trap.machine).value.pc) == 0
let jumpProgram = owner([@[1'u8], @[80'u8, 16, 7, 1], @[0'u8]])
let jump = execute(source(jumpProgram, memory, registers, 1, 0, true), ExecutionStepLimit(1),
  GasCycleLimit(0)).value
assert jump.exit == StepExit.Panic and uint64(machineInfo(jump.machine).value.pc) == 0
assert uint64(machineInfo(jump.machine).value.registers[0]) == 7
var haltRegisters = registers
haltRegisters[0] = RegisterValue(0xffff0000'u64)
let haltProgram = owner([@[1'u8], @[180'u8, 0, 1, 7, 0], @[0'u8]])
let halt = execute(source(haltProgram, memory, haltRegisters, 1, 0, true), ExecutionStepLimit(1),
  GasCycleLimit(0)).value
assert halt.exit == StepExit.Halt and uint64(machineInfo(halt.machine).value.pc) == 0
assert uint64(machineInfo(halt.machine).value.registers[0]) == 7

# The invalid-entry deblob branch panics without charge, while a default machine is a local API error.
for pc in [2'u64, 99'u64, high(uint64)]:
  let info = MachineInfo(pc: CodeAddress(pc), gas: MachineGas(91), blockCharged: false,
    registers: registers)
  let invalid = captureTerminalMachine(trapProgram, memory, info).value
  let run = execute(invalid, ExecutionStepLimit(1), GasCycleLimit(0)).value
  assert run.exit == StepExit.Panic
  var expected = info
  expected.pc = CodeAddress(0)
  same(machineInfo(run.machine).value, expected)
  assert stepOnce(invalid, GasCycleLimit(0)).error == StepError.InvalidMachine
assert execute(default(Machine), ExecutionStepLimit(0), GasCycleLimit(0)).error ==
    StepError.InvalidMachine
assert execute(trapSource, ExecutionStepLimit(0), GasCycleLimit(0)).error ==
    StepError.StepLimitExceeded

# A decrement/branch loop has an independently known instruction count and final register value.
let loopProgram = owner([@[149'u8, 0, 255], @[82'u8, 16, 0, 253], @[0'u8]])
let loopPrice = uint64(blockGas(loopProgram, CodeAddress(0), GasCycleLimit(1000)).value)
let trapPrice = uint64(blockGas(loopProgram, CodeAddress(7), GasCycleLimit(1000)).value)
for count in [1'u64, 2'u64, 17'u64, 10000'u64]:
  var initial = registers
  initial[0] = RegisterValue(count)
  let input = source(loopProgram, memory, initial, 0, loopPrice * count + trapPrice, false)
  assert execute(input, ExecutionStepLimit(count * 2), GasCycleLimit(1000)).error ==
      StepError.StepLimitExceeded
  let finished = execute(input, ExecutionStepLimit(count * 2 + 1), GasCycleLimit(1000)).value
  assert finished.exit == StepExit.Panic
  var expected = machineInfo(input).value
  expected.pc = CodeAddress(0)
  expected.gas = MachineGas(0)
  expected.blockCharged = true
  expected.registers[0] = RegisterValue(0)
  same(machineInfo(finished.machine).value, expected)
  assert uint64(machineInfo(input).value.registers[0]) == count

# Out-of-gas after an earlier block returns the current causing PC and the completed prefix's state.
let gasProgram = owner([@[51'u8, 0, 7], @[1'u8], @[0'u8]])
let firstPrice = uint64(blockGas(gasProgram, CodeAddress(0), GasCycleLimit(1000)).value)
let gasSource = source(gasProgram, memory, registers, 0, firstPrice, false)
assert execute(gasSource, ExecutionStepLimit(2), GasCycleLimit(1000)).error ==
    StepError.StepLimitExceeded
let exhausted = execute(gasSource, ExecutionStepLimit(3), GasCycleLimit(1000)).value
assert exhausted.exit == StepExit.OutOfGas
assert uint64(machineInfo(exhausted.machine).value.pc) == 4
assert uint64(machineInfo(exhausted.machine).value.registers[0]) == 7
assert uint64(machineInfo(exhausted.machine).value.gas) == 0
assert not machineInfo(exhausted.machine).value.blockCharged
# UINT64_MAX is an admissible local budget and cannot overflow the attempted-instruction counter.
assert execute(trapSource, ExecutionStepLimit(high(uint64)), GasCycleLimit(0)).value.exit == StepExit.Panic

# Local specification gates after a completed store still expose no partial machine or source mutation.
let negativeProgram = owner([@[51'u8, 0, 7], @[62'u8, 0, 0, 0, 1, 0], @[1'u8],
  @[82'u8, 16, 0, 128], @[0'u8]])
let negativeSource = source(negativeProgram, memory, registers, 0, high(uint64), false)
assert execute(negativeSource, ExecutionStepLimit(4), GasCycleLimit(1000)).error ==
  StepError.NegativeBranchTarget
let ambiguousProgram = owner([@[51'u8, 0, 7], @[62'u8, 0, 0, 0, 1, 0],
  @[55'u8, 0, 255, 255, 255, 255], @[0'u8]])
let ambiguousSource = source(ambiguousProgram, memory, registers, 0, high(uint64), false)
assert execute(ambiguousSource, ExecutionStepLimit(3), GasCycleLimit(1000)).error ==
  StepError.AmbiguousAccessOrder
assert uint64(load(memory, MemoryAddress(65536), AccessWidth(8)).value) == 0
assert uint64(machineInfo(negativeSource).value.registers[0]) == 0
assert uint64(machineInfo(ambiguousSource).value.registers[0]) == 0
# Per-block simulation exhaustion is independent of the execution step budget and guest gas.
let costlyProgram = owner([@[51'u8, 0, 7], @[1'u8], @[10'u8, 5], @[0'u8]])
let costlySource = source(costlyProgram, memory, registers, 0, high(uint64), false)
assert execute(costlySource, ExecutionStepLimit(3), GasCycleLimit(10)).error ==
  StepError.GasCycleLimitExceeded
assert uint64(machineInfo(costlySource).value.registers[0]) == 0

# Exercise load/store prefixes, fault repair, host suspension and externally advanced host resumption.
proc executionCycle() =
  let program = owner([@[51'u8, 0, 7], @[62'u8, 0, 0, 0, 1, 0], @[10'u8, 5],
    @[51'u8, 1, 9], @[50'u8, 2]])
  let memory = memoryOwner(PageAccess.ReadOnly)
  var regs = default(RegisterFile)
  regs[2] = RegisterValue(0xffff0000'u64)
  let price = uint64(blockGas(program, CodeAddress(0), GasCycleLimit(1000)).value)
  let input = source(program, memory, regs, 0, price, false)
  let fault = execute(input, ExecutionStepLimit(2), GasCycleLimit(1000)).value
  assert fault.exit == StepExit.Fault and uint32(fault.faultPage) == 65536
  let faultInfo = machineInfo(fault.machine).value
  assert uint64(faultInfo.pc) == 3 and uint64(faultInfo.registers[0]) == 7
  assert uint64(faultInfo.gas) == 0 and faultInfo.blockCharged
  let repeated = execute(fault.machine, ExecutionStepLimit(1), GasCycleLimit(0)).value
  assert repeated.exit == StepExit.Fault
  same(machineInfo(repeated.machine).value, faultInfo)
  var page = pageImage(memory, PageIndex(16)).value
  page.access = PageAccess.ReadWrite
  let repaired = withMemory(fault.machine, withPage(memory, page).value).value
  assert execute(repaired, ExecutionStepLimit(1), GasCycleLimit(0)).error ==
      StepError.StepLimitExceeded
  # Discarding a local-limit result cannot leak the private successful prefix store into its source.
  assert uint64(load(memoryOf(repaired).value, MemoryAddress(65536), AccessWidth(8)).value) == 0
  let host = execute(repaired, ExecutionStepLimit(2), GasCycleLimit(0)).value
  assert host.exit == StepExit.Host and uint64(host.hostCall) == 5
  let hostInfo = machineInfo(host.machine).value
  assert uint64(hostInfo.pc) == 9 and uint64(hostInfo.gas) == 0 and hostInfo.blockCharged
  assert uint64(hostInfo.registers[0]) == 7 and uint64(hostInfo.registers[1]) == 0
  assert uint64(load(memoryOf(host.machine).value, MemoryAddress(65536), AccessWidth(8)).value) == 7
  let repeatedHost = execute(host.machine, ExecutionStepLimit(1), GasCycleLimit(0)).value
  assert repeatedHost.exit == StepExit.Host
  same(machineInfo(repeatedHost.machine).value, hostInfo)
  var resumed = hostInfo
  # A trusted environment performs any host mutation and advances PC; execute never calls a host itself.
  resumed.pc = CodeAddress(11)
  resumed.registers[1] = RegisterValue(123)
  let resumedSource = captureMachine(program, memoryOf(host.machine).value, resumed).value
  let stopped = execute(resumedSource, ExecutionStepLimit(2), GasCycleLimit(0)).value
  assert stopped.exit == StepExit.Halt and uint64(machineInfo(stopped.machine).value.pc) == 0
  assert uint64(machineInfo(stopped.machine).value.registers[1]) == 9
  assert uint64(machineInfo(stopped.machine).value.gas) == 0
  assert uint64(load(memoryOf(stopped.machine).value, MemoryAddress(65536), AccessWidth(
      8)).value) == 7
  assert uint64(load(memory, MemoryAddress(65536), AccessWidth(8)).value) == 0
  assert uint64(machineInfo(input).value.registers[0]) == 0

executionCycle()
let before = getOccupiedMem()
# Retained intermediate roots form no cycles; repeated complete invocation lifetimes release all owners.
for iteration in 0..<1000: executionCycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_execution", 1000, before, after)
echo "PVM bounded execution passed"
echo "ARC_RELEASE cycles=1000 unchanged"
