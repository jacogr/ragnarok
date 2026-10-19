# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native Psi_H host-response witnesses using real initialization, suspension and return capture.
## Checks all actions, PC/charged preservation, nominal gas, immutable snapshots and ARC release.

## Verification: {"arc": "pvm_host_response_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, initialize, gas, step, output]
import ../../support/arc_evidence

# Original code executes unlikely, ecalli 7, then jump_ind through initial r0 to halt.
proc initial(): Machine =
  initializeMachine([0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0,
    0, 0, 5, 2, 10, 7, 50, 0, 11], [21'u8, 22], CodeAddress(0), MachineGas(10000),
    InitializationLimits(envelope: InitializationByteLimit(24), program: ProgramByteLimit(9),
      jumps: JumpCountLimit(0), pages: PageLimit(1))).value

# Wait for the actual recursive Host boundary; explicit error selection preserves useful failures.
proc suspended(): StepOutcome =
  let evaluated = execute(initial(), ExecutionStepLimit(2), GasCycleLimit(1000))
  assert evaluated.error == StepError.None
  assert evaluated.value.exit == StepExit.Host
  assert uint64(machineInfo(evaluated.value.machine).value.pc) == 1
  assert uint64(evaluated.value.hostCall) == 7
  evaluated.value

# Retain original CPU state while replacing every host-writable field with distinguishable values.
proc reply(source: StepOutcome, action: HostAction): HostResponse =
  var registers = machineInfo(source.machine).value.registers
  for i in 0..<13:
    # Every register is host-writable; preserve r0 only when an explicit continuation test requests it.
    registers[i] = RegisterValue(uint64(100 + i))
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  page.bytes[0] = 81
  HostResponse(action: action, gas: MachineGas(17), registers: registers,
    memory: captureMemory([page], PageLimit(1)).value)

let host = suspended()
let beforeHost = machineInfo(host.machine).value
assert beforeHost.blockCharged
for action in [HostAction.Continue, HostAction.Halt, HostAction.Panic, HostAction.OutOfGas]:
  let response = reply(host, action)
  let applied = applyHostResponse(host, response)
  assert applied.error == StepError.None
  let outcome = applied.value
  let expected = (if action == HostAction.Continue: StepExit.Continued
    elif action == HostAction.Halt: StepExit.Halt
    elif action == HostAction.Panic: StepExit.Panic else: StepExit.OutOfGas)
  assert outcome.exit == expected
  let info = machineInfo(outcome.machine).value
  assert uint64(info.pc) == (if action == HostAction.Continue: 3'u64 else: 1'u64)
  assert uint64(info.gas) == 17 and info.blockCharged == beforeHost.blockCharged
  for i in 0..<13:
    # Terminal actions also retain every posterior register, rather than rolling the host mutation back.
    assert uint64(info.registers[i]) == uint64(100 + i)
  assert uint64(load(memoryOf(outcome.machine).value, MemoryAddress(65536), AccessWidth(
      1)).value) == 81
  assert pageImage(memoryOf(outcome.machine).value, PageIndex(
      0xfeff0000'u32 div 4096)).value.access ==
    PageAccess.Inaccessible
  assert instruction(programOf(outcome.machine).value, CodeAddress(1)).value.opcode == 10
  assert uint64(machineInfo(host.machine).value.gas) == uint64(beforeHost.gas)
  assert uint64(load(memoryOf(host.machine).value, MemoryAddress(0xfeff0000), AccessWidth(
      1)).value) == 21

# Host-supplied gas is neither recharged nor silently narrowed, at zero and UINT64_MAX alike.
for gasValue in [0'u64, high(uint64)]:
  var response = reply(host, HostAction.Continue)
  response.gas = MachineGas(gasValue)
  response.registers[0] = RegisterValue(0xffff0000'u64)
  let continued = applyHostResponse(host, response).value
  let halted = execute(continued.machine, ExecutionStepLimit(1), GasCycleLimit(0))
  assert halted.error == StepError.None and halted.value.exit == StepExit.Halt
  assert uint64(machineInfo(halted.value.machine).value.gas) == gasValue

# A host may terminate directly with a readable return range at the causing ecalli PC.
var terminating = reply(host, HostAction.Halt)
terminating.registers[7] = RegisterValue(65536)
terminating.registers[8] = RegisterValue(1)
let stopped = applyHostResponse(host, terminating).value
assert uint64(machineInfo(stopped.machine).value.pc) == 1
assert captureOutput(stopped, OutputByteLimit(1)).value == @[81'u8]

# Default responses and absent response-memory owners fail without publishing a machine.
assert applyHostResponse(host, default(HostResponse)).error == StepError.InvalidHostResponse
for action in [HostAction.Continue, HostAction.Halt, HostAction.Panic, HostAction.OutOfGas]:
  var bad = reply(host, action)
  bad.memory = default(Memory)
  assert applyHostResponse(host, bad).error == StepError.InvalidHostResponse
let notHost = default(StepOutcome)
assert applyHostResponse(notHost, reply(host, HostAction.Continue)).error ==
    StepError.InvalidHostSuspension
assert applyHostResponse(stopped, terminating).error == StepError.InvalidHostSuspension
var broken = host
broken.machine = default(Machine)
assert applyHostResponse(broken, terminating).error == StepError.InvalidMachine

# One-step Host outcomes use a following PC, so callers must supply recursive execute suspensions.
let stepped = stepOnce(captureMachine(programOf(host.machine).value, memoryOf(host.machine).value,
  beforeHost).value, GasCycleLimit(0)).value
assert stepped.exit == StepExit.Host
assert applyHostResponse(stepped, terminating).error == StepError.InvalidHostSuspension
# An altered PC that still names valid code cannot masquerade as the causing host instruction.
var altered = beforeHost
altered.pc = CodeAddress(0)
broken = host
broken.machine = captureMachine(programOf(host.machine).value, memoryOf(host.machine).value, altered).value
assert applyHostResponse(broken, terminating).error == StepError.InvalidHostSuspension
altered.pc = CodeAddress(999)
broken.machine = captureTerminalMachine(programOf(host.machine).value, memoryOf(host.machine).value, altered).value
assert applyHostResponse(broken, terminating).error == StepError.InvalidHostSuspension

# Host immediates use zero padding/sign extension, while continuation uses the entire capped skip.
for width in [0, 1, 4, 24]:
  var code = @[2'u8, 10]
  for i in 0..<width:
    # All-one immediate bytes select -1 at any nonzero encoded width; surplus bytes still affect skip.
    code.add(255)
  code.add(50)
  code.add(0)
  var raw = @[0'u8, 0, byte(code.len)]
  for byteValue in code:
    # Encode independent raw code and an explicit opcode mask, without consulting production skip logic.
    raw.add(byteValue)
  var mask = newSeq[byte]((code.len + 7) div 8)
  for offset in [0, 1, width + 2]:
    # Prefix, host and dynamic halt are the only opcode positions.
    mask[offset div 8] = mask[offset div 8] or (1'u8 shl (offset mod 8))
  for bits in mask: raw.add(bits)
  let program = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0)).value
  var cpu = machineInfo(initial()).value
  cpu.blockCharged = true
  let source = captureMachine(program, memoryOf(host.machine).value, cpu).value
  let stoppedAtHost = execute(source, ExecutionStepLimit(2), GasCycleLimit(0)).value
  assert stoppedAtHost.exit == StepExit.Host
  assert uint64(stoppedAtHost.hostCall) == (if width == 0: 0'u64 else: high(uint64))
  var response = reply(stoppedAtHost, HostAction.Continue)
  response.registers[0] = RegisterValue(0xffff0000'u64)
  let continued = applyHostResponse(stoppedAtHost, response).value
  assert uint64(machineInfo(continued.machine).value.pc) == uint64(width + 2)
  assert execute(continued.machine, ExecutionStepLimit(1), GasCycleLimit(0)).value.exit == StepExit.Halt
  if width != 0:
    # Pair a valid Host tag for call 7 with code for call -1; matching only the opcode is insufficient.
    var mismatched = host
    mismatched.machine = stoppedAtHost.machine
    assert applyHostResponse(mismatched, response).error == StepError.InvalidHostSuspension

# Adjacent identical calls must not make a single-step following PC look like a recursive suspension.
block:
  let program = decodeProgram([0'u8, 0, 6, 10, 7, 10, 7, 50, 0, 21],
    CodeAddress(0), ProgramByteLimit(10), JumpCountLimit(0)).value
  var cpu = machineInfo(initial()).value
  cpu.blockCharged = true
  let source = captureMachine(program, memoryOf(host.machine).value, cpu).value
  let single = stepOnce(source, GasCycleLimit(0)).value
  assert applyHostResponse(single, reply(single, HostAction.Continue)).error ==
    StepError.InvalidHostSuspension
  let first = execute(source, ExecutionStepLimit(1), GasCycleLimit(0)).value
  let next = applyHostResponse(first, reply(first, HostAction.Continue)).value
  assert uint64(machineInfo(next.machine).value.pc) == 2
  let second = execute(next.machine, ExecutionStepLimit(1), GasCycleLimit(0)).value
  var response = reply(second, HostAction.Continue)
  response.registers[0] = RegisterValue(0xffff0000'u64)
  let resumed = applyHostResponse(second, response).value
  assert uint64(machineInfo(resumed.machine).value.pc) == 4
  assert execute(resumed.machine, ExecutionStepLimit(1), GasCycleLimit(0)).value.exit == StepExit.Halt

# A valid empty memory owner is accepted; absent/default owners are not interchangeable with it.
var emptyResponse = reply(host, HostAction.Halt)
emptyResponse.memory = captureMemory([], PageLimit(0)).value
assert applyHostResponse(host, emptyResponse).error == StepError.None

# The original suspension is reusable; each reply produces an independent immutable successor.
proc cycle() =
  let source = suspended()
  var response = reply(source, HostAction.Continue)
  response.registers[0] = RegisterValue(0xffff0000'u64)
  response.registers[7] = RegisterValue(65536)
  response.registers[8] = RegisterValue(1)
  response.gas = MachineGas(0)
  let first = applyHostResponse(source, response).value
  response.registers[8] = RegisterValue(0)
  response.memory = store(response.memory, MemoryAddress(65536), AccessWidth(1), RegisterValue(99)).value
  let second = applyHostResponse(source, response).value
  let firstHalt = execute(first.machine, ExecutionStepLimit(1), GasCycleLimit(0)).value
  assert captureOutput(firstHalt, OutputByteLimit(1)).value == @[81'u8]
  let secondHalt = execute(second.machine, ExecutionStepLimit(1), GasCycleLimit(0)).value
  assert captureOutput(secondHalt, OutputByteLimit(0)).value.len == 0
  assert uint64(load(memoryOf(first.machine).value, MemoryAddress(65536), AccessWidth(1)).value) == 81
  assert uint64(load(memoryOf(second.machine).value, MemoryAddress(65536), AccessWidth(1)).value) == 99
  assert uint64(machineInfo(source.machine).value.pc) == 1

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Source, replies and descendants share acyclic immutable children without retaining prior executions.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_host_response", 1000, before, after)
echo "PVM host response passed"
echo "ARC_RELEASE cycles=1000 unchanged"
