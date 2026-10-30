# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay dependent arithmetic checkpoints through charged host continuations and every block shortage.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/[gas, plan as gas_plan, memo as gas_memo]
import ../../../src/pvm/step

type
  Refusal = enum ## Fallible callbacks use an independent local refusal domain; successful witnesses select only genuine responses.
    Refused
  Checkpoint = object ## A frozen complete CPU observation after one arithmetic mutation.
    pc, start, charge: uint64
    registers: RegisterFile
  Context = object ## One synchronous replay borrows its own bounded expected checkpoint list.
    checkpoints: seq[Checkpoint]
    calls: int
    budget: uint64

proc word(data: string, at, width: int): uint64 =
  ## Read a fixed field only after its entire enclosing structure has been bounded.
  result = 0
  for i in 0..<width:
    # Little-endian fixture framing is independent of the production instruction parser.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc respond(context: var Context, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Observe every register and gas checkpoint, then continue without modifying guest state.
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 13
  assert context.calls < context.checkpoints.len
  let wanted = context.checkpoints[context.calls]
  let cpu = machineInfo(stopped.machine).value
  assert uint64(cpu.pc) == wanted.pc and cpu.blockCharged
  assert context.budget >= wanted.charge and uint64(cpu.gas) == context.budget - wanted.charge
  assert uint64(cpu.gasDeficit) == 0
  for i in 0..<13:
    # Earlier mutations and source/destination aliases must compose into the full expected array.
    assert uint64(cpu.registers[i]) == uint64(wanted.registers[i])
  inc context.calls
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
    registers: cpu.registers, memory: memoryOf(stopped.machine).value)

proc unchanged(source: Machine, initial: RegisterFile, budget: uint64, memory: Memory) =
  ## Every completed or refused replay preserves its original CPU and immutable empty-memory owner.
  let cpu = machineInfo(source).value
  assert uint64(cpu.pc) == 0 and uint64(cpu.gas) == budget and uint64(cpu.gasDeficit) == 0
  assert not cpu.blockCharged and memoryOf(source).value == memory
  for i in 0..<13:
    assert uint64(cpu.registers[i]) == uint64(initial[
        i]) # Include registers not modified by the final checkpoint.

proc respondFallible(context: var Context, stopped: StepOutcome): HostResult[Refusal] {.raises: [].} =
  ## Both public callback forms observe the exact same independently frozen checkpoint contract.
  hostSuccess[Refusal](respond(context, stopped))

proc run(source: Machine, context: var Context, mode: int, plan: GasPlan, memo: GasMemo,
    steps = ExecutionStepLimit(175), calls = HostCallLimit(85)): StepResult =
  ## Select real policy overloads without changing shared instruction/dispatch budgets.
  case mode
  of 0: executeWithHost(source, context, respond, steps, calls, GasCycleLimit(10000))
  of 1: executeWithHost(source, context, respond, steps, calls, plan)
  else: executeWithHost(source, context, respond, steps, calls, memo)

proc runFallible(source: Machine, context: var Context, mode: int, plan: GasPlan, memo: GasMemo,
    steps = ExecutionStepLimit(175), calls = HostCallLimit(85)): HostExecutionResult[Refusal] =
  ## Preserve the typed execution-failure alternative for exact local budget refusals.
  case mode
  of 0: executeWithHost(source, context, respondFallible, steps, calls, GasCycleLimit(10000))
  of 1: executeWithHost(source, context, respondFallible, steps, calls, plan)
  else: executeWithHost(source, context, respondFallible, steps, calls, memo)

proc replay(source: Machine, context: var Context, mode: int, fallible: bool,
    plan: GasPlan, memo: GasMemo): StepOutcome =
  ## Only successful engine results grant the completed guest outcome; OOG is a guest outcome, not a local error.
  if fallible:
    let completed = runFallible(source, context, mode, plan, memo)
    assert completed.error == HostExecutionError.None
    completed.value
  else:
    let completed = run(source, context, mode, plan, memo)
    assert completed.error == StepError.None
    completed.value

var data = ""
try:
  # Missing frozen input is a setup failure, never an empty corpus success.
  data = readFile(getEnv("RAGNAROK_PVM_REGISTER_CHAINS"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMCHN01" and word(data, 8, 4) == 8
var cursor = 12
for row in 0..<8:
  # Exact fixed dimensions bound every subsequent multiplication, allocation and narrowing.
  assert data.len - cursor >= 116
  let length = word(data, cursor, 4)
  assert word(data, cursor + 4, 4) == 5 and word(data, cursor + 8, 4) == 85
  var initial = default(RegisterFile)
  for i in 0..<13:
    # Preserve every original register, including high bits and untouched sentinels.
    initial[i] = RegisterValue(word(data, cursor + 12 + i * 8, 8))
  cursor += 116
  assert data.len - cursor >= 100 + 85 * 120
  var starts = default(array[5, uint64])
  var prices = default(array[5, uint64])
  var cycles = default(array[5, uint64])
  var total = 0'u64
  for i in 0..<5:
    # Small independently computed block prices cannot overflow the complete invocation budget.
    starts[i] = word(data, cursor, 4)
    prices[i] = word(data, cursor + 4, 8)
    cycles[i] = word(data, cursor + 12, 8)
    assert starts[i] < 2048 and prices[i] > 0 and prices[i] < 10000
    assert cycles[i] > 0 and cycles[i] < 10000
    total += prices[i]
    cursor += 20
  var checkpoints: seq[Checkpoint] = @[]
  for i in 0..<85:
    # Checkpoint arrays are copied scalars; the callback retains no alias to the decoder or source machine.
    var item = Checkpoint(pc: word(data, cursor, 4), start: word(data, cursor + 4, 4),
      charge: word(data, cursor + 8, 8), registers: default(RegisterFile))
    assert item.pc < 2048 and item.start == starts[i div 17] and item.charge <= total
    for r in 0..<13:
      # The entire posterior register file is mandatory at every host suspension.
      item.registers[r] = RegisterValue(word(data, cursor + 16 + r * 8, 8))
    checkpoints.add(item)
    cursor += 120
  assert length >= 4 and length <= 2048 and length <= uint64(data.len - cursor)
  var wire: seq[byte] = @[]
  for i in 0..<int(length):
    # Both execution engines consume these original instruction bytes and marked opcode positions.
    wire.add(byte(data[cursor + i]))
  cursor += int(length)
  let program = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(2048), JumpCountLimit(0)).value
  let memory = captureMemory(default(seq[PageImage]), PageLimit(0)).value
  for i in 0..<5:
    # Public gas calculations must agree with the independent per-block model and exact local limit.
    assert uint64(blockGas(program, CodeAddress(starts[i]), GasCycleLimit(cycles[i])).value) ==
        prices[i]
    assert blockGas(program, CodeAddress(starts[i]), GasCycleLimit(cycles[i] - 1)).error ==
      GasError.CycleLimitExceeded
  let prepared = newGasPlan(program, GasPlanLimits(blocks: GasPlanBlockLimit(5),
    bytes: GasPlanByteLimit(16384), cycles: GasCycleLimit(10000)))
  assert prepared.error == GasPlanError.None
  for i in 0..<5:
    assert uint64(blockGas(prepared.value, CodeAddress(starts[i])).value) == prices[
        i] # The complete table must match every independent block price.
  for scenario in 0..<7:
    # Two terminal successes and five independently unaffordable block entries retain their own prefixes.
    let blocked = scenario - 2
    var budget = total + (if scenario == 0: 7'u64 else: 0'u64)
    if scenario >= 2:
      # The selected block is exactly one gas unit short after every preceding block completes.
      budget = prices[blocked] - 1
      for i in 0..<blocked: budget += prices[i]
    let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(
        budget),
      blockCharged: false, registers: initial)).value
    for fallible in [false, true]:
      let learned = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(16384),
          cycles: GasCycleLimit(10000)))
      assert learned.error == GasMemoError.None
      for mode in 0..<4:
        # A fresh memo starts cold for each scenario/callback form; the next replay retains exactly those successful source-bound facts.
        var context = Context(checkpoints: checkpoints, calls: 0, budget: budget)
        let outcome = replay(source, context, mode, fallible, prepared.value, learned.value)
        let cpu = machineInfo(outcome.machine).value
        let calls = if scenario < 2: 85 else: blocked * 17
        assert context.calls == calls and uint64(cpu.gasDeficit) == 0
        if scenario < 2:
          # Final trap normalizes PC only at the recursive execution boundary.
          assert outcome.exit == StepExit.Panic and uint64(cpu.pc) == 0 and cpu.blockCharged
          assert uint64(cpu.gas) == budget - total
        else:
          # A refused block publishes no arithmetic or host prefix from that block.
          assert outcome.exit == StepExit.OutOfGas and not cpu.blockCharged
          assert uint64(cpu.pc) == starts[blocked] and uint64(cpu.gas) == prices[blocked] - 1
        let wanted = if calls == 0: initial else: checkpoints[calls - 1].registers
        for i in 0..<13:
          # All completed prefixes and original aliases retain complete independent register expectations.
          assert uint64(cpu.registers[i]) == uint64(wanted[i])
          assert uint64(machineInfo(source).value.registers[i]) == uint64(initial[i])
        assert uint64(machineInfo(source).value.gas) == budget and not machineInfo(
            source).value.blockCharged
        assert memoryOf(outcome.machine).value == memory
        unchanged(source, initial, budget, memory)
        assert gasMemoInfo(learned.value).value.pricedBlocks == (if mode < 2: 0'u64 elif scenario <
            2: 5'u64 else: uint64(blocked+1))
        if scenario == 0:
          # Reusing warm prices never grants another instruction attempt or host dispatch; completed callback effects remain visible on local refusal.
          for shortage in 0..<2:
            var limited = Context(checkpoints: checkpoints, calls: 0, budget: budget)
            let steps = ExecutionStepLimit(if shortage == 0: 174'u64 else: 175'u64)
            let calls = HostCallLimit(if shortage == 0: 85'u64 else: 84'u64)
            let wanted = if shortage == 0: StepError.StepLimitExceeded else: StepError.HostCallLimitExceeded
            if fallible:
              let refused = runFallible(source, limited, mode, prepared.value, learned.value, steps, calls)
              assert refused.error == HostExecutionError.ExecutionFailure and
                  refused.executionError == wanted
            else:
              let refused = run(source, limited, mode, prepared.value, learned.value, steps, calls)
              assert refused.error == wanted
            assert limited.calls == (if shortage == 0: 85 else: 84)
            unchanged(source, initial, budget, memory)
assert cursor == data.len

echo "PVM dependent register chains passed: 8 programs, 448 policy/callback scenarios"
