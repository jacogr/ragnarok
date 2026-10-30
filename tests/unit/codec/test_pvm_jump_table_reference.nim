# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent GP jump-table width/count witnesses, including zero-width runtime behavior.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/[gas, plan as gas_plan, memo as gas_memo]
import ../../../src/pvm/step

type
  Reason = enum ## The typed callback path has its own local error domain, distinct from all guest outcomes.
    Refused
  Context = object ## Host checkpoints retain no program/cache identity and belong to one synchronous replay.
    calls: int
    prepaid: bool

proc respond(context: var Context, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Three host/jump laps warm the same ordinal while independently checking full gas and prior host mutations.
  let cpu = machineInfo(stopped.machine).value
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 0
  assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  assert uint64(cpu.gas) == 607-(if context.prepaid: 0'u64 else: 100'u64)-uint64(
      context.calls+1)*100
  for i in 0..<13:
    let wanted = if i == 8: 2'u64 elif i == 12: uint64(context.calls) else: 0'u64
    assert uint64(cpu.registers[i]) == wanted # Every previous callback write and original jump operand must survive cache hits.
  inc context.calls
  var registers = cpu.registers
  registers[12] = RegisterValue(uint64(context.calls))
  HostResponse(action: (if context.calls == 3: HostAction.Panic else: HostAction.Continue),
    gas: cpu.gas, gasDeficit: GasDeficit(0), registers: registers, memory: memoryOf(
        stopped.machine).value)

proc respondFallible(context: var Context, stopped: StepOutcome): HostResult[Reason] {.raises: [].} =
  ## Both callback APIs apply the same independently expected checkpoint and posterior write.
  hostSuccess[Reason](respond(context, stopped))

proc hosted(source: Machine, context: var Context, mode: int, fallible: bool,
    plan: GasPlan, memo: GasMemo): StepOutcome =
  ## Use the actual six-attempt/three-dispatch overloads; a terminal third reply needs no additional guest attempt.
  if fallible:
    let done = if mode == 0: executeWithHost(source, context, respondFallible, ExecutionStepLimit(
        6), HostCallLimit(3), GasCycleLimit(103))
      elif mode == 1: executeWithHost(source, context, respondFallible, ExecutionStepLimit(6),
          HostCallLimit(3), plan)
      else: executeWithHost(source, context, respondFallible, ExecutionStepLimit(6), HostCallLimit(
          3), memo)
    assert done.error == HostExecutionError.None
    done.value
  else:
    let done = if mode == 0: executeWithHost(source, context, respond, ExecutionStepLimit(6),
        HostCallLimit(3), GasCycleLimit(103))
      elif mode == 1: executeWithHost(source, context, respond, ExecutionStepLimit(6),
          HostCallLimit(3), plan)
      else: executeWithHost(source, context, respond, ExecutionStepLimit(6), HostCallLimit(3), memo)
    assert done.error == StepError.None
    done.value

proc verify(source: Machine, registers: RegisterFile, pc, gas: uint64, charged: bool,
    memory: Memory) =
  ## Even invalid jumps preserve all CPU values except the normative terminal PC/gas/paid transitions.
  let cpu = machineInfo(source).value
  assert uint64(cpu.pc) == pc and uint64(cpu.gas) == gas and uint64(cpu.gasDeficit) == 0
  assert cpu.blockCharged == charged and memoryOf(source).value == memory
  for i in 0..<13: assert uint64(cpu.registers[i]) == uint64(registers[i])

proc qualify(owner: Program, reachesHost: bool) =
  ## Compare raw/JAM logical table semantics under every pricing policy, including initially unpaid interior entry and repeated target hits.
  let memory = captureMemory([], PageLimit(0)).value
  var registers = default(RegisterFile)
  registers[8] = RegisterValue(2)
  let prepared = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(1),
      bytes: GasPlanByteLimit(32), cycles: GasCycleLimit(103)))
  assert prepared.error == GasPlanError.None and uint64(blockGas(prepared.value, CodeAddress(
      0)).value) == 100
  for prepaid in [false, true]:
    let learned = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(32),
        cycles: GasCycleLimit(103)))
    assert learned.error == GasMemoError.None
    let source = captureMachine(owner, memory, MachineInfo(pc: CodeAddress(2), gas: MachineGas(607),
      gasDeficit: GasDeficit(0), blockCharged: prepaid, registers: registers)).value
    for mode in 0..<4:
      for fallible in [false, true]:
        # Exact ordinal0 is either repeatedly valid or a guest panic; neither pricing nor the callback form changes the decode profile.
        var context = Context(calls: 0, prepaid: prepaid)
        let outcome = hosted(source, context, mode, fallible, prepared.value, learned.value)
        assert outcome.exit == StepExit.Panic and context.calls == (if reachesHost: 3 else: 0)
        var expected = registers
        expected[12] = RegisterValue(uint64(context.calls))
        let gas = 607-(if prepaid: 0'u64 else: 100'u64)-(if reachesHost: 300'u64 else: 0'u64)
        verify(outcome.machine, expected, 0, gas, true, memory)
        verify(source, registers, 2, 607, prepaid, memory)
      assert gasMemoInfo(learned.value).value.pricedBlocks == (if mode < 2 or (prepaid and
          not reachesHost): 0'u64 else: 1'u64)

for width in 0..255:
  for count in 0..1:
    # Literal host0 at PC0, jump_ind r8 at PC2; E_z zero entries require no encoder.
    var wire = @[byte(count), byte(width), 4'u8]
    for index in 0..<(count * width): wire.add(0)
    for octet in [10'u8, 0, 50, 8, 5]: wire.add(octet)
    let parsed = decodeProgram(wire, CodeAddress(2), ProgramByteLimit(512), JumpCountLimit(1))
    assert parsed.error == (if width > 4: ProgramError.InvalidProgram else: ProgramError.None)
    if width > 4:
      continue # Current deblob rejects oversized widths before any executable owner can exist.
    if count == 1:
      assert uint64(jumpTarget(parsed.value, JumpIndex(0)).value) == 0
    else:
      assert jumpTarget(parsed.value, JumpIndex(0)).error == ProgramError.InvalidIndex
    let jam = decodeJamProgram(wire, CodeAddress(2), ProgramByteLimit(512), JumpCountLimit(1))
    assert jam.error == (if width > 4: ProgramError.InvalidProgram else: ProgramError.None)
    if width <= 4:
      let entry = jumpTarget(jam.value, JumpIndex(0))
      if count == 1 and width != 0:
        assert entry.error == ProgramError.None and uint64(entry.value) == 0
      else:
        assert entry.error == ProgramError.InvalidIndex
    # The declared count still consumes local policy even if the JAM profile hides width-zero entries.
    if count == 1:
      let limited = decodeJamProgram(wire, CodeAddress(2), ProgramByteLimit(512), JumpCountLimit(0))
      assert limited.error == ProgramError.LimitExceeded
    var registers = default(RegisterFile)
    registers[8] = RegisterValue(2)
    let source = captureMachine(parsed.value, captureMemory([], PageLimit(0)).value,
      MachineInfo(pc: CodeAddress(2), gas: MachineGas(1000), blockCharged: true,
        registers: registers)).value
    if width <= 4:
      let compatible = captureMachine(jam.value, captureMemory([], PageLimit(0)).value,
        machineInfo(source).value).value
      let observed = execute(compatible, ExecutionStepLimit(2), GasCycleLimit(1000))
      assert observed.error == StepError.None
      assert observed.value.exit == (if count == 1 and width !=
          0: StepExit.Host else: StepExit.Panic)
      if observed.value.exit == StepExit.Host: assert uint64(observed.value.hostCall) == 0
    qualify(parsed.value, count == 1)
    qualify(jam.value, count == 1 and width != 0)
    let first = stepOnce(source, GasCycleLimit(1000))
    assert first.error == StepError.None
    assert first.value.exit == (if count == 1: StepExit.Continued else: StepExit.Panic)
    assert uint64(machineInfo(first.value.machine).value.pc) == (if count == 1: 0'u64 else: 2'u64)
    let completed = execute(source, ExecutionStepLimit(2), GasCycleLimit(1000))
    assert completed.error == StepError.None
    assert completed.value.exit == (if count == 1: StepExit.Host else: StepExit.Panic)
    if count == 1:
      assert uint64(completed.value.hostCall) == 0
    for index in 0..<13:
      # Neither the dynamic jump nor host suspension writes a register, including the original source.
      assert uint64(machineInfo(completed.value.machine).value.registers[index]) == uint64(
          registers[index])
      assert uint64(machineInfo(source).value.registers[index]) == uint64(registers[index])
    assert uint64(machineInfo(source).value.pc) == 2
    assert uint64(machineInfo(source).value.gas) == 1000 and machineInfo(source).value.blockCharged

echo "PVM paper jump-table witnesses passed: 512; current width bounds; GP-PVM-006 recorded"
