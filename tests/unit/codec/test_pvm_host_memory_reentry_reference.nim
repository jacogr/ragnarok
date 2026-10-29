# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen mixed loops retain full CPU/memory snapshots through host replacement, permission faults and paid reentry.
# @@Verification={"arc": "pvm_host_memory_reentry_reference_arc_release"}
import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, gas, gas_plan, gas_memo, step]
import ../../support/arc_evidence

type
  Retained = object ## Every saved immutable machine has independently derived CPU, bytes and permissions.
    machine: Machine
    cpu: MachineInfo
    scalar: uint64
    marks: array[2, byte]
    access: array[2, PageAccess]
  HostContext = object ## Test hosts retain observations, never execution policy or a mutable guest workspace.
    calls, iterations, initial, address, budget, price: uint64
    input: RegisterFile
    access: array[2, PageAccess]
    saved: seq[Retained]
  PricingMode {.pure.} = enum ## The frozen same-program oracle applies to each execution policy.
    Dynamic, Planned, Memo, Prepared
  HostRefusal {.pure.} = enum ## Selected successes remain separate from this zero-valued refusal reason.
    Refused

proc word(data: string, at, width: int): uint64 =
  ## Read only fixed fields within a previously bounded fixture header.
  result = 0
  # Each little-endian byte contributes at its fixed, sub-word shift.
  for i in 0..<width: result = result or (uint64(byte(data[at+i])) shl (8*i))

proc images(address, scalar: uint64, marks: array[2, byte],
    access: array[2, PageAccess]): array[2, PageImage] =
  ## Independent byte equations own the complete expected image, including inaccessible native snapshot bytes.
  result = default(array[2, PageImage])
  for page in 0..<2:
    # Ordered headers and unrelated sentinel bytes must survive every scalar replacement.
    result[page] = PageImage(index: PageIndex(uint32(16+page)), access: access[page],
      bytes: default(array[4096, byte]))
    for i in 0..<4096: result[page].bytes[i] = 33
    result[page].bytes[32] = marks[page]
  for i in 0..<8:
    # Only the admitted scalar span replaces the two complete independent page images.
    let offset = int(address-65536)+i # Framing admits only 0x10000 or 0x10fff, so both page indices are bounded.
    result[offset div 4096].bytes[offset mod 4096] = byte((scalar shr (8*i)) and 255)

proc check(record: Retained, address: uint64) =
  ## Later host owners and repair snapshots cannot change an earlier complete observation.
  let cpu = machineInfo(record.machine).value
  assert uint64(cpu.pc) == uint64(record.cpu.pc)
  assert uint64(cpu.gas) == uint64(record.cpu.gas), "independent prepared full-state gas trace"
  assert cpu.blockCharged == record.cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  # Compare untouched registers as well as the three loop/host mutations.
  for i in 0..<13: assert uint64(cpu.registers[i]) == uint64(record.cpu.registers[i])
  let expected = images(address, record.scalar, record.marks, record.access)
  let memory = memoryOf(record.machine).value
  let indices = pageIndices(memory)
  assert indices.error == MachineError.None
  let ordered = indices.value
  assert ordered.len == 2 and uint32(ordered[0]) == 16 and uint32(ordered[1]) == 17
  for page in 0..<2:
    # Inaccessible native images still retain their independently authored snapshot bytes.
    let actual = pageImage(memory, expected[page].index).value
    assert actual.access == expected[page].access and actual.bytes == expected[page].bytes

proc retain(context: var HostContext, machine: Machine, pc, gas: uint64,
    charged: bool, registers: RegisterFile, scalar: uint64, marks: array[2, byte]) =
  ## Only independently checked snapshots enter the retained predecessor set.
  let record = Retained(machine: machine, cpu: MachineInfo(pc: CodeAddress(pc),
    gas: MachineGas(gas), gasDeficit: GasDeficit(0), blockCharged: charged, registers: registers),
    scalar: scalar, marks: marks, access: context.access)
  check(record, context.address)
  context.saved.add(record)

proc loopRegisters(context: HostContext, iteration: uint64, incremented: bool): RegisterFile =
  ## Modular arithmetic derives every changed register; untouched registers retain literal fixture sentinels.
  result = context.input
  result[7] = RegisterValue(context.initial+iteration+(if incremented: 1'u64 else: 0'u64))
  result[8] = RegisterValue(iteration*context.initial+iteration*(iteration+1) div 2)
  result[10] = RegisterValue(iteration)

proc respond(context: var HostContext, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Host13 replaces memory then withdraws write access; host14 observes the repaired guest store before replacing it again.
  assert suspension.exit == StepExit.Host and context.calls < 2*context.iterations
  let iteration = context.calls div 2
  let prior = context.initial+iteration
  let cpu = machineInfo(suspension.machine).value
  var registers = loopRegisters(context, iteration, context.calls mod 2 != 0)
  var scalar = prior
  var marks = [33'u8, 33'u8]
  if context.calls mod 2 == 0:
    # The next loop starts from the preceding second-host replacement, or the initial immutable input.
    if iteration > 0: marks = [byte(116+iteration), byte(176+iteration)]
    assert uint64(suspension.hostCall) == 13
    retain(context, suspension.machine, 3, context.budget-(iteration+1)*context.price,
      true, registers, scalar, marks)
    registers[7] = RegisterValue(prior+1)
    marks = [byte(17+iteration), byte(77+iteration)]
    context.access = [PageAccess.ReadOnly, PageAccess.Inaccessible]
  else:
    # Failed stores must not have changed a byte before both repairs; the successful store is visible here.
    assert uint64(suspension.hostCall) == 14
    scalar = prior+1
    marks = [byte(17+iteration), byte(77+iteration)]
    retain(context, suspension.machine, 8, context.budget-(iteration+1)*context.price,
      true, registers, scalar, marks)
    registers[8] = RegisterValue(uint64(registers[8])+scalar)
    marks = [byte(117+iteration), byte(177+iteration)]
    context.access = [PageAccess.ReadWrite, PageAccess.ReadWrite]
  let replacement = captureMemory(images(context.address, scalar, marks, context.access), PageLimit(2))
  assert replacement.error == MachineError.None
  inc context.calls
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
    registers: registers, memory: replacement.value)

proc respondFallible(context: var HostContext, suspension: StepOutcome): HostResult[
    HostRefusal] {.raises: [].} =
  ## The selected success branch transports exactly the response checked by the ordinary callback.
  hostSuccess[HostRefusal](respond(context, suspension))

proc runReply(source: Machine, context: var HostContext, mode: PricingMode,
    cycles: uint64, plan: GasPlan, memo: GasMemo, owner: PreparedProgram): StepOutcome =
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
    of PricingMode.Prepared:
      # One source-bound owner survives every host permission replacement and repaired paid retry.
      executeWithHost(source, context, respond, steps, hosts, owner)
  assert checked.error == StepError.None
  checked.value

proc runFallible(source: Machine, context: var HostContext, mode: PricingMode,
    cycles: uint64, plan: GasPlan, memo: GasMemo, owner: PreparedProgram): StepOutcome =
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
    of PricingMode.Prepared:
      # One source-bound owner survives every host permission replacement and repaired paid retry.
      executeWithHost(source, context, respondFallible, steps, hosts, owner)
  assert checked.error == HostExecutionError.None
  checked.value

proc checkNativeProgress(owner: PreparedProgram, before: PreparedInfo, progressed: bool) =
  ## Eligible complete loops must execute real native calls; checked refusals may not manufacture them.
  let after = preparedInfo(owner).value
  when defined(pvmArm64Jit) or defined(pvmX86Jit):
    when defined(pvmArm64JitRefuse) or defined(pvmX86JitRefuse):
      # A real storage-refusal build preserves the same literal state trace through checked fallback.
      assert after.nativeCalls == before.nativeCalls and after.nativeOperations ==
          before.nativeOperations
    else:
      if progressed and after.jitPlatformSupported:
        # The loop's admitted add/branch prefix is eligible on both maintained native backends.
        assert after.nativeCalls > before.nativeCalls and after.nativeOperations >
            before.nativeOperations,
          "independent prepared native execution trace"
      else:
        # Initial unpaid gas refusal executes no instruction, including when the owner is already warm.
        assert after.nativeCalls == before.nativeCalls and after.nativeOperations ==
            before.nativeOperations
  else:
    # The ordinary registered suite intentionally qualifies the checked fallback without a native claim.
    assert after.nativeCalls == 0 and after.nativeOperations == 0

proc entryTraces(program: Program, memory: Memory, registers: RegisterFile, initial,
    address, price, haltPrice: uint64, owner: PreparedProgram) =
  ## Reorder existing frozen load/host, store/host and terminal PCs through one genuine source owner.
  for entry in [20'u64, 5, 0, 5, 20, 0]:
    # Descending then permuted entries share executable facts while every CPU/memory input is fresh.
    var input = registers
    if entry == 5: input[7] = RegisterValue(initial+1) # This is the frozen first host's literal register reply.
    for paid in [false, true]:
      # Paid zero-gas resumes must bypass pricing; unpaid starts test exact and one-short fixed block prices.
      let charge = if entry == 20: haltPrice else: price
      for credit in [0'u64, charge-1, charge]:
        # The frozen corpus prices block starts0/20; interior5 is tested unpaid only at zero credit.
        if entry == 5 and not paid and credit != 0: continue
        let cpu = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(credit),
          gasDeficit: GasDeficit(0), blockCharged: paid, registers: input)
        let captured = captureMachine(program, memory, cpu)
        assert captured.error == MachineError.None
        let source = captured.value
        let original = Retained(machine: source, cpu: cpu, scalar: initial,
          marks: [33'u8, 33'u8], access: [PageAccess.ReadWrite, PageAccess.ReadWrite])
        let exact = if entry == 20: 1'u64 else: 2'u64
        for attempts in 0'u64..exact:
          # Zero, one-short and exact source attempts retain private partial progress on local refusal.
          let executed = execute(source, ExecutionStepLimit(attempts), owner)
          if attempts == 0 or ((paid or credit == charge) and attempts < exact):
            assert executed.error == StepError.StepLimitExceeded,
              "independent prepared partial attempt trace"
          else:
            assert executed.error == StepError.None
            let outcome = executed.value
            let refused = not paid and credit < charge
            let expectedExit = if refused: StepExit.OutOfGas elif entry ==
                20: StepExit.Halt else: StepExit.Host
            assert outcome.exit == expectedExit, "independent prepared entry exit trace"
            if not refused and entry != 20:
              # The exact two-op prefix reaches the literal host without invoking a callback.
              assert uint64(outcome.hostCall) == (if entry == 0: 13'u64 else: 14'u64)
            var expected = input
            if not refused and entry == 0: expected[7] = RegisterValue(initial)
            let pc = if refused: entry elif entry == 20: 0'u64 elif entry == 0: 3'u64 else: 8'u64
            let scalar = if not refused and entry == 5: initial+1 else: initial
            let expectedCpu = MachineInfo(pc: CodeAddress(pc),
              gas: MachineGas(if paid or refused: credit else: credit-charge),
              gasDeficit: GasDeficit(0), blockCharged: not refused, registers: expected)
            check(Retained(machine: outcome.machine, cpu: expectedCpu, scalar: scalar,
              marks: [33'u8, 33'u8], access: [PageAccess.ReadWrite, PageAccess.ReadWrite]), address)
          check(original, address) # Every unpublished partial write and successful successor leave the real source unchanged.
    if entry == 5:
      # Reuse that owner for the frozen paid store after host permission withdrawal, then repair exact selected faults.
      var access = [PageAccess.ReadOnly, PageAccess.Inaccessible]
      let captured = captureMemory(images(address, initial, [33'u8, 33'u8], access), PageLimit(2))
      assert captured.error == MachineError.None
      let cpu = MachineInfo(pc: CodeAddress(5), gas: MachineGas(0), gasDeficit: GasDeficit(0),
        blockCharged: true, registers: input)
      let initialMachine = captureMachine(program, captured.value, cpu)
      assert initialMachine.error == MachineError.None
      var current = initialMachine.value
      var retained = @[Retained(machine: current, cpu: cpu, scalar: initial,
        marks: [33'u8, 33'u8], access: access)]
      let faults = if address == 0x10fff: 2 else: 1
      for index in 0..<faults:
        # Cross-page missing-second precedes read-only-first; one paid source attempt returns the precise fault.
        let executed = execute(current, ExecutionStepLimit(1), owner)
        assert executed.error == StepError.None
        let outcome = executed.value
        let page = if address == 0x10fff and index == 0: 1 else: 0
        assert outcome.exit == StepExit.Fault and uint32(outcome.faultPage) == uint32(
            65536+page*4096)
        check(Retained(machine: outcome.machine, cpu: cpu, scalar: initial,
          marks: [33'u8, 33'u8], access: access), address)
        access[page] = PageAccess.ReadWrite
        let repaired = withPage(memoryOf(outcome.machine).value,
          images(address, initial, [33'u8, 33'u8], access)[page])
        assert repaired.error == MachineError.None
        let replaced = withMemory(outcome.machine, repaired.value)
        assert replaced.error == MachineError.None
        current = replaced.value
        retained.add(Retained(machine: current, cpu: cpu, scalar: initial,
          marks: [33'u8, 33'u8], access: access))
      let retried = execute(current, ExecutionStepLimit(2), owner)
      assert retried.error == StepError.None and retried.value.exit == StepExit.Host
      assert uint64(retried.value.hostCall) == 14
      var expectedCpu = cpu
      expectedCpu.pc = CodeAddress(8)
      check(Retained(machine: retried.value.machine, cpu: expectedCpu, scalar: initial+1,
        marks: [33'u8, 33'u8], access: access), address)
      for record in retained: check(record, address) # Repairs and retries cannot mutate any prior owner or hidden page image.

proc runCase(program: Program, memory: Memory, registers: RegisterFile, initial, address,
    iterations, price, haltPrice, cycles: uint64, mode: PricingMode, warm, fallible: bool,
    scenario: int, plan: GasPlan, memo: GasMemo, owner: PreparedProgram): tuple[calls,
        faults: uint64] =
  ## One bounded invocation series owns cold policy, callback progress, fault repair and all retained snapshots.
  let before = preparedInfo(owner).value
  let total = iterations*price+haltPrice
  let budget = if scenario == 0: total+7 elif scenario == 1: total
    elif scenario == 2: total-1 else: price-1
  let source = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0),
    gas: MachineGas(budget), registers: registers, blockCharged: false)).value
  var context = HostContext(calls: 0, iterations: iterations, initial: initial, address: address,
    budget: budget, price: price, input: registers,
    access: [PageAccess.ReadWrite, PageAccess.ReadWrite], saved: @[])
  retain(context, source, 0, budget, false, registers, initial, [33'u8, 33'u8])
  var selected = memo
  if mode == PricingMode.Memo and not warm:
    let fresh = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(512),
        cycles: GasCycleLimit(cycles)))
    assert fresh.error == GasMemoError.None
    selected = fresh.value
  var current = source
  var final = default(StepOutcome)
  var done = false
  var faults = 0'u64
  for attempt in 0..int(2*iterations):
    # At most two faults per loop plus one terminal execution bounds every reentry independently of guest gas.
    let outcome = if fallible: runFallible(current, context, mode, cycles, plan, selected, owner)
      else: runReply(current, context, mode, cycles, plan, selected, owner)
    if outcome.exit != StepExit.Fault:
      # A terminal or gas outcome ends the bounded repair series without manufacturing another callback.
      final = outcome
      done = true
      break
    assert scenario != 3 and context.calls mod 2 == 1
    let iteration = context.calls div 2
    assert iteration < iterations and context.access[0] == PageAccess.ReadOnly
    let missingHigher = address == 0x10fff and context.access[1] == PageAccess.Inaccessible
    let page = if missingHigher: 1 else: 0
    assert uint32(outcome.faultPage) == uint32(65536+page*4096)
    let expectedRegisters = loopRegisters(context, iteration, true)
    let marks = [byte(17+iteration), byte(77+iteration)]
    retain(context, outcome.machine, 5, budget-(iteration+1)*price, true,
      expectedRegisters, initial+iteration, marks)
    context.access[page] = PageAccess.ReadWrite
    let replacement = images(address, initial+iteration, marks, context.access)[page]
    let repaired = withPage(memoryOf(outcome.machine).value, replacement)
    assert repaired.error == MachineError.None
    current = withMemory(outcome.machine, repaired.value).value
    retain(context, current, 5, budget-(iteration+1)*price, true,
      expectedRegisters, initial+iteration, marks)
    inc faults
  assert done
  let progressed = scenario != 3
  assert context.calls == (if progressed: 2*iterations else: 0'u64)
  assert faults == (if not progressed: 0'u64 elif address == 0x10fff: 2*iterations else: iterations)
  var expected = registers
  var scalar = initial
  var marks = [33'u8, 33'u8]
  if progressed:
    # Every completed loop contributes one stored scalar and one modular host accumulation.
    expected[7] = RegisterValue(initial+iterations)
    expected[8] = RegisterValue(iterations*initial+iterations*(iterations+1) div 2)
    expected[10] = RegisterValue(iterations)
    scalar = initial+iterations
    marks = [byte(116+iterations), byte(176+iterations)]
  let gas = if scenario < 2: budget-total elif scenario == 2: haltPrice-1 else: budget
  if scenario < 2:
    # Exact and surplus gas complete the paid halt block.
    assert final.exit == StepExit.Halt
  else:
    # Initial or final block refusal retains the independently expected unpaid PC and balance.
    assert final.exit == StepExit.OutOfGas
  retain(context, final.machine, (if scenario == 2: 20'u64 else: 0'u64), gas,
    scenario < 2, expected, scalar, marks)
  if mode == PricingMode.Memo:
    # Learned facts survive refusals without being mistaken for paid guest gas.
    assert gasMemoInfo(selected).value.pricedBlocks == (if warm or progressed: 2'u64 else: 1'u64)
  for record in context.saved: check(record, address) # Every old CPU/memory alias survives all later replacement and repair.
  if mode == PricingMode.Prepared: checkNativeProgress(owner, before, progressed)
  (context.calls, faults)

var data = ""
try:
  data = readFile(getEnv("RAGNAROK_PVM_MIXED_PROGRAM"))
except:
  quit 2 # Missing independent inputs cannot be treated as skipped verification.
assert data.len >= 12 and data[0..7] == "PVMMIX01" and word(data, 8, 4) == 32
var cursor = 12
var cases = 0
var callbacks = 0'u64
var faults = 0'u64
var nativeCalls, nativeOperations = 0'u64
for row in 0..<32:
  # Bound record extents and each scalar domain before conversion or allocation.
  assert data.len-cursor >= 268
  let at = cursor
  let length = word(data, at, 4)
  let iterations = word(data, at+4, 4)
  let address = word(data, at+8, 4)
  let initial = word(data, at+12, 8)
  let price = word(data, at+28, 8)
  let cycles = word(data, at+36, 8)
  let haltPrice = word(data, at+44, 8)
  assert iterations in [1'u64, 2, 7, 31] and address in [0x10000'u64, 0x10fff]
  assert price == 103 and cycles == 106 and haltPrice == 22 and word(data, at+52, 8) == 25
  cursor += 268
  assert length >= 4 and length <= 64 and length <= uint64(data.len-cursor)
  var wire = newSeq[byte](int(length))
  for i in 0..<wire.len: wire[i] = byte(data[cursor+i])
  cursor += wire.len
  let parsed = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert parsed.error == ProgramError.None
  let program = parsed.value
  var registers = default(RegisterFile)
  for i in 0..<13: registers[i] = RegisterValue(word(data, at+60+i*8, 8))
  assert uint64(registers[7]) == 77 and uint64(registers[8]) == 0 and uint64(registers[10]) == 0
  assert (uint64(registers[9]) and 0xffffffff'u64) == address
  for i in 0..<13:
    # The unchanged fixture's final registers independently protect the arithmetic oracle used at all repair checkpoints.
    let wanted = if i == 7: initial+iterations
      elif i == 8: iterations*initial+iterations*(iterations+1) div 2
      elif i == 10: iterations else: uint64(registers[i])
    assert word(data, at+164+i*8, 8) == wanted
  assert word(data, at+20, 8) == initial+iterations
  let memory = captureMemory(images(address, initial, [33'u8, 33'u8],
    [PageAccess.ReadWrite, PageAccess.ReadWrite]), PageLimit(2)).value
  let prepared = newGasPlan(program, GasPlanLimits(blocks: GasPlanBlockLimit(2),
      bytes: GasPlanByteLimit(512), cycles: GasCycleLimit(cycles)))
  let learned = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(512),
      cycles: GasCycleLimit(cycles)))
  assert prepared.error == GasPlanError.None and learned.error == GasMemoError.None
  let plan = prepared.value
  let memo = learned.value
  let execution = newPreparedProgram(program, defaultPreparedLimits(GasCycleLimit(cycles)))
  assert execution.error == PreparationError.None
  let owner = execution.value # This exact owner remains alive through both warm orders and every host repair.
  entryTraces(program, memory, registers, initial, address, price, haltPrice, owner)
  assert uint64(blockGas(memo, CodeAddress(0)).value) == price
  assert uint64(blockGas(memo, CodeAddress(20)).value) == haltPrice
  for mode in [PricingMode.Dynamic, PricingMode.Planned, PricingMode.Memo, PricingMode.Prepared]:
    for warm in [false, true]:
      # Dynamic/immutable-plan policies run once; memo/prepared identities survive the second complete pass.
      if warm and mode notin [PricingMode.Memo, PricingMode.Prepared]: continue # Reused owners must retain no invocation state.
      for fallible in [false, true]:
        # Both public host adapters consume the same state sequence and finite repair budget.
        for scenario in 0..<4:
          let observed = runCase(program, memory, registers, initial, address, iterations,
            price, haltPrice, cycles, mode, warm, fallible, scenario, plan, memo, owner)
          inc cases
          callbacks += observed.calls
          faults += observed.faults
  if row == 1:
    # Repeat complete crossing-repair owner graphs after a calibration cycle; no source, callback or memo retains a retired context.
    discard runCase(program, memory, registers, initial, address, iterations, price, haltPrice,
      cycles, PricingMode.Memo, false, true, 1, plan, memo, owner)
    let before = getOccupiedMem()
    for cycle in 0..<1000:
      discard runCase(program, memory, registers, initial, address, iterations, price, haltPrice,
        cycles, PricingMode.Memo, false, true, 1, plan, memo, owner)
    let after = getOccupiedMem()
    assert before == after
    recordArcRelease("pvm_host_memory_reentry_reference", 1000, before, after)
  let native = preparedInfo(owner).value
  nativeCalls += native.nativeCalls
  nativeOperations += native.nativeOperations
assert cursor == data.len and cases == 1536 and callbacks == 23616 and faults == 17712

echo "PVM host memory reentry passed: 1536 cases, 23616 callbacks, 17712 repaired faults"
echo "Prepared owner entry traces passed: 32 owners, 192 reordered entries"
when defined(pvmArm64Jit) or defined(pvmX86Jit):
  # Private native/refused qualification consumes actual cumulative execution receipts, never cache occupancy alone.
  echo "PREPARED_TRACE_NATIVE,", nativeCalls, ",", nativeOperations
echo "ARC_RELEASE cycles=1000 unchanged"
