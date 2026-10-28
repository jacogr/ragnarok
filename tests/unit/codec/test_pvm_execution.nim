# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native host-call and bounded recursive-Psi execution witnesses.
## Checks stepOnce/execute PC rules, suspension/retry, private work limits and ARC release evidence.

# @@Verification={"arc": "pvm_execution_arc_release"}

import std/assertions
import std/syncio
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
import ../../support/testing_arc_evidence

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
  assert uint64(actual.gasDeficit) == uint64(expected.gasDeficit)
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

# Repeated blocks still pay on every visit; new calls cannot inherit a previous program/limit's price.
block priceReuseIsolation:
  var initial = registers
  initial[0] = RegisterValue(17)
  let input = source(loopProgram, memory, initial, 0, loopPrice * 17 + trapPrice + 7, false)
  let completed = execute(input, ExecutionStepLimit(35), GasCycleLimit(loopPrice + 3))
  assert completed.error == StepError.None and completed.value.exit == StepExit.Panic
  assert uint64(machineInfo(completed.value.machine).value.gas) == 7
  assert uint64(machineInfo(completed.value.machine).value.registers[0]) == 0
  # A lower policy ceiling on the identical source must refuse freshly, without progress.
  assert execute(input, ExecutionStepLimit(35), GasCycleLimit(loopPrice + 2)).error ==
      StepError.GasCycleLimitExceeded
  assert uint64(machineInfo(input).value.gas) == loopPrice * 17 + trapPrice + 7
  assert uint64(machineInfo(input).value.registers[0]) == 17
  let different = owner([@[2'u8], @[0'u8]])
  let differentPrice = uint64(blockGas(different, CodeAddress(0), GasCycleLimit(1000)).value)
  let other = source(different, memory, registers, 0, differentPrice + 7, false)
  let stopped = execute(other, ExecutionStepLimit(2), GasCycleLimit(1000)).value
  assert stopped.exit == StepExit.Panic and uint64(machineInfo(stopped.machine).value.gas) == 7
  # Single-step calls remain independent and cannot reuse an execution's successful simulation.
  assert stepOnce(other, GasCycleLimit(0)).error == StepError.GasCycleLimitExceeded
  same(machineInfo(other).value, machineInfo(source(different, memory, registers, 0,
      differentPrice + 7, false)).value)

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

# Completed negative-target panic and wrapping-memory fault retain successful prefixes without mutating source aliases.
let negativeProgram = owner([@[51'u8, 0, 7], @[62'u8, 0, 0, 0, 1, 0], @[1'u8],
  @[82'u8, 16, 0, 128], @[0'u8]])
let negativeSource = source(negativeProgram, memory, registers, 0, high(uint64), false)
let negative = execute(negativeSource, ExecutionStepLimit(4), GasCycleLimit(1000))
assert negative.error == StepError.None and negative.value.exit == StepExit.Panic
assert uint64(machineInfo(negative.value.machine).value.registers[0]) == 7
assert uint64(load(memoryOf(negative.value.machine).value, MemoryAddress(65536), AccessWidth(
    8)).value) == 7
let wrappingProgram = owner([@[51'u8, 0, 7], @[62'u8, 0, 0, 0, 1, 0],
  @[55'u8, 0, 255, 255, 255, 255], @[0'u8]])
let wrappingSource = source(wrappingProgram, memory, registers, 0, high(uint64), false)
let wrapping = execute(wrappingSource, ExecutionStepLimit(3), GasCycleLimit(1000))
assert wrapping.error == StepError.None and wrapping.value.exit == StepExit.Fault
assert uint32(wrapping.value.faultPage) == 0xfffff000'u32
assert uint64(machineInfo(wrapping.value.machine).value.registers[0]) == 7
assert uint64(load(memoryOf(wrapping.value.machine).value, MemoryAddress(65536), AccessWidth(
    8)).value) == 7
assert uint64(load(memory, MemoryAddress(65536), AccessWidth(8)).value) == 0
assert uint64(machineInfo(negativeSource).value.registers[0]) == 0
assert uint64(machineInfo(wrappingSource).value.registers[0]) == 0
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

proc cursorSnapshotCycle() =
  ## Retain every externally observable step root while private execution overwrites the same page twice and stops at a host.
  let program = owner([@[51'u8, 0, 7], @[62'u8, 0, 0, 0, 1, 0], @[51'u8, 0, 9],
      @[62'u8, 0, 0, 0, 1, 0], @[10'u8, 5], @[0'u8]])
  let input = source(program, memoryOwner(PageAccess.ReadWrite), default(RegisterFile), 0, high(
      uint64), false)
  var roots = @[input]
  for index in 0..<4:
    let once = stepOnce(roots[index], GasCycleLimit(1000))
    assert once.error == StepError.None and once.value.exit == StepExit.Continued
    roots.add(once.value.machine) # These immutable aliases remain live while all independent cursor runs execute.
  let host = execute(input, ExecutionStepLimit(5), GasCycleLimit(1000))
  assert host.error == StepError.None and host.value.exit == StepExit.Host
  assert uint64(host.value.hostCall) == 5
  same(machineInfo(host.value.machine).value, machineInfo(roots[4]).value)
  for start in 0..<4:
    assert execute(roots[start], ExecutionStepLimit(uint64(4-start)), GasCycleLimit(1000)).error ==
        StepError.StepLimitExceeded # Earlier private writes are discarded on local refusal, even with retained intermediate roots.
    let resumed = execute(roots[start], ExecutionStepLimit(uint64(5-start)), GasCycleLimit(1000))
    assert resumed.error == StepError.None and resumed.value.exit == StepExit.Host
    same(machineInfo(resumed.value.machine).value, machineInfo(host.value.machine).value)
    assert pageImage(memoryOf(resumed.value.machine).value, PageIndex(16)).value.bytes ==
        pageImage(memoryOf(host.value.machine).value, PageIndex(16)).value.bytes
  for index in 0..<roots.len:
    let expected = if index < 2: 0'u64 elif index < 4: 7'u64 else: 9'u64
    assert uint64(load(memoryOf(roots[index]).value, MemoryAddress(65536), AccessWidth(8)).value) == expected
  assert uint64(load(memoryOf(host.value.machine).value, MemoryAddress(65536), AccessWidth(
      8)).value) == 9

proc prefixExitCycle(registers: RegisterFile) =
  ## Compare all stopped CPU/page fields against retained public steps after a committed register/store prefix.
  for faulting in [true, false]:
    let ending = if faulting: @[55'u8, 1, 0, 16, 1, 0] else: @[10'u8, 5]
    let program = owner([@[51'u8, 0, 7], @[62'u8, 0, 0, 0, 1, 0], ending, @[0'u8]])
    let input = source(program, memoryOwner(PageAccess.ReadWrite), registers, 0, high(uint64), false)
    let first = stepOnce(input, GasCycleLimit(1000)).value
    let second = stepOnce(first.machine, GasCycleLimit(1000)).value
    let once = stepOnce(second.machine, GasCycleLimit(1000)).value
    let run = execute(input, ExecutionStepLimit(3), GasCycleLimit(1000)).value
    assert run.exit == (if faulting: StepExit.Fault else: StepExit.Host)
    assert once.exit == run.exit
    var expected = machineInfo(once.machine).value
    expected.pc = machineInfo(second.machine).value.pc # Recursive host normalization retains the causing PC.
    same(machineInfo(run.machine).value, expected)
    if faulting:
      assert uint32(run.faultPage) == 69632 and uint32(once.faultPage) == 69632
    else:
      assert uint64(run.hostCall) == 5 and uint64(once.hostCall) == 5
    let actualPage = pageImage(memoryOf(run.machine).value, PageIndex(16)).value
    assert actualPage.access == PageAccess.ReadWrite
    for index in 0..<4096:
      # The complete prefix page has only the stored low byte; failed loads/host exits change no neighbors.
      assert actualPage.bytes[index] == (if index == 0: 7'u8 else: 0'u8)
    same(machineInfo(input).value, machineInfo(source(program, memoryOf(input).value,
      registers, 0, high(uint64), false)).value)
    assert uint64(load(memoryOf(input).value, MemoryAddress(65536), AccessWidth(8)).value) == 0
    assert uint64(load(memoryOf(first.machine).value, MemoryAddress(65536), AccessWidth(
        8)).value) == 0
    assert uint64(load(memoryOf(second.machine).value, MemoryAddress(65536), AccessWidth(
        8)).value) == 7

type WorkspaceExit {.pure.} = enum ## Explicit observations span both sides of adaptive writer activation.
  Host, Fault, Panic, Halt, OutOfGas

proc workspacePage(memory: Memory, value: int) =
  ## Complete page expectations retain untouched canaries outside the low eight-byte store.
  let image = pageImage(memory, PageIndex(16)).value
  assert image.access == PageAccess.ReadWrite
  for offset in 0..<4096:
    let wanted = if offset == 0: byte(value) elif offset == 510: 27'u8
      elif offset == 512: 37'u8 elif offset == 4095: 99'u8 else: 0'u8
    assert image.bytes[offset] == wanted

proc workspaceCase(count: int, ending: WorkspaceExit, baseRegisters: RegisterFile) =
  ## Compare staged execution against retained immutable public-step roots before and after the fourth store.
  var parts: seq[seq[byte]] = @[]
  for index in 0..<count:
    parts.add(@[51'u8, 0, byte(index+1)])
    parts.add(@[62'u8, 0, 0, 0, 1, 0])
  var expectedExit = StepExit.Panic
  var extra = 0
  case ending
  of WorkspaceExit.Host:
    parts.add(@[10'u8, 7])
    expectedExit = StepExit.Host
  of WorkspaceExit.Fault:
    parts.add(@[55'u8, 1, 0, 16, 1, 0])
    expectedExit = StepExit.Fault
  of WorkspaceExit.Panic:
    discard # The final authored trap below causes this terminal observation.
  of WorkspaceExit.Halt:
    parts.add(@[50'u8, 2])
    expectedExit = StepExit.Halt
  of WorkspaceExit.OutOfGas:
    parts.add(@[1'u8]) # Fallthrough enters the unpaid final trap block after all stores committed.
    expectedExit = StepExit.OutOfGas
    extra = 1
  parts.add(@[0'u8])
  let program = owner(parts)
  let empty = memoryOwner(PageAccess.ReadWrite)
  var image = pageImage(empty, PageIndex(16)).value
  image.bytes[510] = 27
  image.bytes[512] = 37
  image.bytes[4095] = 99
  let memory = withPage(empty, image).value
  var registers = baseRegisters
  registers[2] = RegisterValue(0xffff0000'u64)
  let input = source(program, memory, registers, 0, 0, true)
  var roots = @[input]
  for index in 0..<count*2:
    let evaluated = stepOnce(roots[roots.len-1], GasCycleLimit(1000))
    assert evaluated.error == StepError.None and evaluated.value.exit == StepExit.Continued
    roots.add(evaluated.value.machine)
  var beforeExit = roots[roots.len-1]
  if extra != 0:
    let crossed = stepOnce(beforeExit, GasCycleLimit(1000)).value
    assert crossed.exit == StepExit.Continued
    beforeExit = crossed.machine
  let once = stepOnce(beforeExit, GasCycleLimit(1000)).value
  let run = execute(input, ExecutionStepLimit(uint64(count*2+extra+1)), GasCycleLimit(1000))
  assert run.error == StepError.None and run.value.exit == expectedExit and once.exit == expectedExit
  var expected = machineInfo(once.machine).value
  if expectedExit in {StepExit.Panic, StepExit.Halt}: expected.pc = CodeAddress(0)
  elif expectedExit == StepExit.Host: expected.pc = machineInfo(beforeExit).value.pc
  same(machineInfo(run.value.machine).value, expected)
  if expectedExit == StepExit.Fault: assert uint32(run.value.faultPage) == 69632
  if expectedExit == StepExit.Host: assert uint64(run.value.hostCall) == 7
  workspacePage(memoryOf(run.value.machine).value, count)
  assert execute(input, ExecutionStepLimit(uint64(count*2)), GasCycleLimit(1000)).error ==
      StepError.StepLimitExceeded
  for index in 0..<roots.len:
    workspacePage(memoryOf(roots[index]).value, index div 2) # All older snapshots survive private staging and discarded prefixes.
  same(machineInfo(input).value, machineInfo(source(program, memory, registers, 0, 0, true)).value)

type
  WorkspaceReason {.pure.} = enum ## The typed callback shares the same checked workspace continuation.
    Refused
  WorkspaceContext = object ## One published mid-program snapshot remains alive during a second staged epoch.
    calls: int
    retained: Machine

proc workspaceReply(context: var WorkspaceContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Observe the completed fourth store and replace memory before the next guest segment starts.
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 7
  assert uint64(machineInfo(stopped.machine).value.registers[0]) == 4
  assert uint64(load(memoryOf(stopped.machine).value, MemoryAddress(65536), AccessWidth(
      8)).value) == 4
  context.retained = stopped.machine
  inc context.calls
  let cpu = machineInfo(stopped.machine).value
  var registers = cpu.registers
  registers[10] = RegisterValue(77)
  let replaced = store(memoryOf(stopped.machine).value, MemoryAddress(65536), AccessWidth(8),
      RegisterValue(99)).value
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
      registers: registers, memory: replaced)

proc workspaceTyped(context: var WorkspaceContext, stopped: StepOutcome): HostResult[
    WorkspaceReason] {.raises: [].} =
  ## Success uses the same posterior state in the fallible host API.
  hostSuccess[WorkspaceReason](workspaceReply(context, stopped))

proc workspaceHostCycle(baseRegisters: RegisterFile) =
  ## Two four-store epochs must freeze around the callback and restart from its replaced memory.
  var parts: seq[seq[byte]] = @[]
  for value in 1..4:
    parts.add(@[51'u8, 0, byte(value)])
    parts.add(@[62'u8, 0, 0, 0, 1, 0])
  parts.add(@[10'u8, 7])
  parts.add(@[58'u8, 1, 0, 0, 1, 0]) # r1 observes the host's complete replacement before any new store.
  for value in 5..8:
    parts.add(@[51'u8, 0, byte(value)])
    parts.add(@[62'u8, 0, 0, 0, 1, 0])
  parts.add(@[50'u8, 2])
  let program = owner(parts)
  var registers = baseRegisters
  registers[2] = RegisterValue(0xffff0000'u64)
  let input = source(program, memoryOwner(PageAccess.ReadWrite), registers, 0, 0, true)
  for typed in [false, true]:
    var context = WorkspaceContext(calls: 0, retained: default(Machine))
    var completed = default(StepOutcome)
    if typed:
      let run = executeWithHost(input, context, workspaceTyped, ExecutionStepLimit(19),
          HostCallLimit(1), GasCycleLimit(0))
      assert run.error == HostExecutionError.None
      completed = run.value
    else:
      let run = executeWithHost(input, context, workspaceReply, ExecutionStepLimit(19),
          HostCallLimit(1), GasCycleLimit(0))
      assert run.error == StepError.None
      completed = run.value
    assert completed.exit == StepExit.Halt and context.calls == 1
    let cpu = machineInfo(completed.machine).value
    assert uint64(cpu.pc) == 0 and uint64(cpu.gas) == 0 and cpu.blockCharged
    for index in 0..<13:
      let wanted = if index == 0: 8'u64 elif index == 1: 99'u64 elif index ==
          10: 77'u64 else: uint64(registers[index])
      assert uint64(cpu.registers[index]) == wanted
    assert uint64(load(memoryOf(completed.machine).value, MemoryAddress(65536), AccessWidth(
        8)).value) == 8
    assert uint64(load(memoryOf(context.retained).value, MemoryAddress(65536), AccessWidth(
        8)).value) == 4
    assert uint64(load(memoryOf(input).value, MemoryAddress(65536), AccessWidth(8)).value) == 0

workspaceHostCycle(registers)

for count in [1, 3, 4, 5, 9]:
  for ending in [WorkspaceExit.Host, WorkspaceExit.Fault, WorkspaceExit.Panic, WorkspaceExit.Halt,
      WorkspaceExit.OutOfGas]:
    workspaceCase(count, ending, registers)

executionCycle()
cursorSnapshotCycle()
prefixExitCycle(registers)
let before = getOccupiedMem()
# Retained intermediate roots form no cycles; repeated complete invocation lifetimes release all owners.
for iteration in 0..<1000:
  executionCycle()
  workspaceHostCycle(registers)
  workspaceCase(5, WorkspaceExit.Host, registers)
  workspaceCase(5, WorkspaceExit.Fault, registers)
  prefixExitCycle(registers)
  cursorSnapshotCycle() # Every retained root and temporary cursor must return to the same warm ARC baseline.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_execution", 1000, before, after)
echo "PVM bounded execution passed"
echo "ARC_RELEASE cycles=1000 unchanged"
