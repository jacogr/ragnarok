# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete GP-derived guest loops compare memory, host replies, branches and exact gas boundaries.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, gas, gas_plan, gas_memo, step]

type HostContext = object ## Synchronous test hosts own only scalar expectations and callback progress.
  calls, iterations, initial, address, budget, price: uint64

type
  PricingMode {.pure.} = enum ## Each execution policy consumes the same frozen guest and complete expected state.
    Dynamic, Planned, Memo
  HostRefusal {.pure.} = enum ## The zero ordinal remains a real refusal reason; selected success carries the reply separately.
    Refused

proc word(data: string, at, width: int): uint64 =
  ## Decode fixed corpus fields only after their enclosing record has been bounded.
  result = 0
  for i in 0..<width:
    # Expected framing is independent of production instruction decoding.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc memoryValue(memory: Memory, address: uint64): uint64 =
  ## Inspect copied page bytes independently of the guest's load/store helpers.
  result = 0
  for i in 0..<8:
    # The fixture proves these eight physical bytes belong to two captured pages above the guard zone.
    let physical = address + uint64(i)
    let image = pageImage(memory, PageIndex(uint32(physical div 4096))).value
    result = result or (uint64(image.bytes[int(physical mod 4096)]) shl (8 * i))

proc respond(context: var HostContext, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Host13 increments the loaded scalar; host14 accumulates the guest's already-published store.
  assert suspension.exit == StepExit.Host and context.calls < 2 * context.iterations
  let cpu = machineInfo(suspension.machine).value
  let memory = memoryOf(suspension.machine).value
  let iteration = context.calls div 2
  let prior = context.initial + iteration
  assert uint64(cpu.gas) == context.budget - (iteration + 1) * context.price and cpu.blockCharged
  assert uint64(cpu.registers[10]) == iteration
  var registers = cpu.registers
  if context.calls mod 2 == 0:
    # The guest load must observe the prior completed iteration, including 64-bit wraparound.
    assert uint64(suspension.hostCall) == 13 and uint64(cpu.pc) == 3
    assert uint64(registers[7]) == prior and memoryValue(memory, context.address) == prior
    registers[7] = RegisterValue(prior + 1)
  else:
    # The second callback sees the store before the guest increments its counter and branches.
    assert uint64(suspension.hostCall) == 14 and uint64(cpu.pc) == 8
    assert uint64(registers[7]) == prior + 1 and memoryValue(memory, context.address) == prior + 1
    registers[8] = RegisterValue(uint64(registers[8]) + prior + 1)
  inc context.calls
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
    registers: registers, memory: memory)

proc respondFallible(context: var HostContext, suspension: StepOutcome): HostResult[
    HostRefusal] {.raises: [].} =
  ## The selected success branch transports exactly the response checked by the ordinary callback.
  hostSuccess[HostRefusal](respond(context, suspension))

proc runReply(source: Machine, context: var HostContext, mode: PricingMode,
    cycles: uint64, plan: GasPlan, memo: GasMemo): StepOutcome =
  ## Each response-only policy retains identical attempt/callback budgets and the same invocation-local context.
  let steps = ExecutionStepLimit(6 * context.iterations + 1)
  let hosts = HostCallLimit(2 * context.iterations)
  let checked = case mode
    of PricingMode.Dynamic:
      executeWithHost(source, context, respond, steps, hosts, GasCycleLimit(cycles))
    of PricingMode.Planned:
      executeWithHost(source, context, respond, steps, hosts, plan)
    of PricingMode.Memo:
      executeWithHost(source, context, respond, steps, hosts, memo)
  assert checked.error == StepError.None
  checked.value

proc runFallible(source: Machine, context: var HostContext, mode: PricingMode,
    cycles: uint64, plan: GasPlan, memo: GasMemo): StepOutcome =
  ## Fallible host successes must preserve the same complete memory/register prefix at every gas boundary.
  let steps = ExecutionStepLimit(6 * context.iterations + 1)
  let hosts = HostCallLimit(2 * context.iterations)
  let checked = case mode
    of PricingMode.Dynamic:
      executeWithHost(source, context, respondFallible, steps, hosts, GasCycleLimit(cycles))
    of PricingMode.Planned:
      executeWithHost(source, context, respondFallible, steps, hosts, plan)
    of PricingMode.Memo:
      executeWithHost(source, context, respondFallible, steps, hosts, memo)
  assert checked.error == HostExecutionError.None
  checked.value

var data = ""
try:
  # Frozen complete-program inputs are mandatory; test execution never regenerates expectations.
  data = readFile(getEnv("RAGNAROK_PVM_MIXED_PROGRAM"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMMIX01" and word(data, 8, 4) == 32
var cursor = 12
var checkedScenarios = 0
var checkedCalls = 0'u64
for row in 0..<32:
  # Bound the complete header, scalar domains and raw blob before any narrowing or allocation.
  assert data.len - cursor >= 268
  let at = cursor
  let length = word(data, at, 4)
  let iterations = word(data, at + 4, 4)
  let address = word(data, at + 8, 4)
  let initial = word(data, at + 12, 8)
  let price = word(data, at + 28, 8)
  let cycles = word(data, at + 36, 8)
  let haltPrice = word(data, at + 44, 8)
  let haltCycles = word(data, at + 52, 8)
  assert iterations >= 1 and iterations <= 31 and address in [0x10000'u64, 0x10fff'u64]
  assert price > 0 and price < 1000 and haltPrice > 0 and haltPrice < 1000
  assert cycles > 0 and cycles < 1000 and haltCycles > 0 and haltCycles <= cycles
  cursor += 268
  assert length >= 4 and length <= 64 and length <= uint64(data.len - cursor)
  var wire: seq[byte] = @[]
  for i in 0..<int(length):
    # Preserve original code and masks instead of reassembling through the production decoder.
    wire.add(byte(data[cursor + i]))
  cursor += int(length)
  let program = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0)).value
  assert uint64(blockGas(program, CodeAddress(0), GasCycleLimit(cycles)).value) == price
  assert uint64(blockGas(program, CodeAddress(20), GasCycleLimit(haltCycles)).value) == haltPrice
  assert blockGas(program, CodeAddress(0), GasCycleLimit(cycles - 1)).error ==
      GasError.CycleLimitExceeded
  var registers = default(RegisterFile)
  for i in 0..<13:
    # Full input registers include nonzero untouched sentinels and upper bits in the effective base.
    registers[i] = RegisterValue(word(data, at + 60 + i * 8, 8))
  var images = default(array[2, PageImage])
  for page in 0..<2:
    # The two-page placement exercises both ordinary and crossing u64 reads/stores.
    images[page] = PageImage(index: PageIndex(uint32(16 + page)), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
    for i in 0..<4096: images[page].bytes[i] = 33
  for i in 0..<8:
    # Only the initial scalar replaces sentinel bytes; neighboring memory must survive every host/loop.
    let offset = int(address - 0x10000) + i
    images[offset div 4096].bytes[offset mod 4096] = byte((initial shr (8 * i)) and 255)
  let memory = captureMemory(images, PageLimit(2)).value
  let total = iterations * price + haltPrice
  let prepared = newGasPlan(program, GasPlanLimits(blocks: GasPlanBlockLimit(2),
    bytes: GasPlanByteLimit(512), cycles: GasCycleLimit(cycles)))
  assert prepared.error == GasPlanError.None
  let plan = prepared.value
  assert gasPlanInfo(plan).value.blockCount == 2
  let learned = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(512),
    cycles: GasCycleLimit(cycles)))
  assert learned.error == GasMemoError.None
  let memo = learned.value
  assert gasMemoInfo(memo).value.pricedBlocks == 0
  assert uint64(blockGas(memo, CodeAddress(0)).value) == price
  assert uint64(blockGas(memo, CodeAddress(20)).value) == haltPrice
  for mode in [PricingMode.Dynamic, PricingMode.Planned, PricingMode.Memo]:
    for warm in [false, true]:
      if warm and mode != PricingMode.Memo: continue # Only a lazy memo has learned facts to distinguish.
      for fallible in [false, true]:
        for scenario in 0..<4:
          # Exact and surplus success, final-block shortage and initial-block shortage share the same guest.
          let budget = if scenario == 0: total + 7 elif scenario == 1: total
            elif scenario == 2: total - 1 else: price - 1
          let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0),
              gas: MachineGas(budget),
            blockCharged: false, registers: registers)).value
          var context = HostContext(calls: 0, iterations: iterations, initial: initial,
            address: address,
            budget: budget, price: price)
          var selectedMemo = memo
          if mode == PricingMode.Memo and not warm:
            # Each cold scenario starts with an explicitly successful empty source-bound table.
            let cold = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(512),
              cycles: GasCycleLimit(cycles)))
            assert cold.error == GasMemoError.None
            selectedMemo = cold.value
          let outcome = if fallible: runFallible(source, context, mode, cycles, plan, selectedMemo)
            else: runReply(source, context, mode, cycles, plan, selectedMemo)
          inc checkedScenarios
          checkedCalls += context.calls
          if mode == PricingMode.Memo:
            # A cold first-block refusal learns one price; every other case reaches or already knows both blocks.
            let learnedBlocks = if warm or scenario != 3: 2'u64 else: 1'u64
            assert gasMemoInfo(selectedMemo).value.pricedBlocks == learnedBlocks
          let posterior = machineInfo(outcome.machine).value
          let progressed = scenario != 3
          assert context.calls == (if progressed: 2 * iterations else: 0'u64)
          if scenario < 2:
            # Successful dynamic halt normalizes the native PC after paying the final block exactly once.
            assert outcome.exit == StepExit.Halt and uint64(posterior.pc) == 0 and
                posterior.blockCharged
            assert uint64(posterior.gas) == budget - total
          else:
            # Both underfunded boundaries preserve the current block's uncharged state and completed prefix.
            assert outcome.exit == StepExit.OutOfGas and not posterior.blockCharged
            assert uint64(posterior.pc) == (if scenario == 2: 20'u64 else: 0'u64)
            assert uint64(posterior.gas) == (if scenario == 2: haltPrice - 1 else: budget)
          for i in 0..<13:
            # The independent complete-program oracle includes accumulated host replies and loop counter state.
            let expected = word(data, at + (if progressed: 164 else: 60) + i * 8, 8)
            assert uint64(posterior.registers[i]) == expected
            assert uint64(machineInfo(source).value.registers[i]) == uint64(registers[i])
          let scalar = if progressed: word(data, at + 20, 8) else: initial
          for page in 0..<2:
            # Complete byte comparison and source aliases detect extra writes that scalar-only checks miss.
            let actual = pageImage(memoryOf(outcome.machine).value, PageIndex(uint32(16 + page))).value
            assert actual.access == PageAccess.ReadWrite
            for i in 0..<4096:
              let physical = 0x10000'u64 + uint64(page * 4096 + i)
              let expected = if physical >= address and physical - address < 8:
                byte((scalar shr (8 * int(physical - address))) and 255) else: 33'u8
              assert actual.bytes[i] == expected
            assert pageImage(memoryOf(source).value, PageIndex(uint32(16 + page))).value.bytes ==
                images[page].bytes
          assert uint64(machineInfo(source).value.gas) == budget and not machineInfo(
              source).value.blockCharged
assert cursor == data.len
assert checkedScenarios == 1024 and checkedCalls == 15744

echo "PVM mixed-program cross-check passed: 32 programs, 1024 policy/host scenarios"
