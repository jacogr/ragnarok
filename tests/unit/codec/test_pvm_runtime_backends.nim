# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Run real explicit engines through the same checked host continuation and immutable memory contract.
## Optional-runtime and standalone builds retain distinct refusal and execution witnesses.
import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, step, gas]

type HostFailure = enum ## Callback refusal is distinct from every guest/engine exit.
  Refused

type Context = object ## Test-local state observes host count and controls explicit callback refusal.
  calls: int
  refuse, malformed, terminal: bool
  prepared: PreparedProgram
  reentry: bool

type PageReplyContext = object ## Posterior memory is a copied immutable snapshot; actions cover every accepted reply kind.
  action: HostAction
  memory: Memory
  calls: int

proc pageReply(context: var PageReplyContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Deliberately supply admitted or oversized host memory without altering the causing CPU/register state.
  inc context.calls
  let cpu = machineInfo(stopped.machine).value
  HostResponse(action: context.action, gas: cpu.gas, registers: cpu.registers,
      memory: context.memory)

proc falliblePageReply(context: var PageReplyContext, stopped: StepOutcome): HostResult[
    HostFailure] {.raises: [].} =
  ## Fallible adapters must enforce the same prepared response limits as direct callbacks.
  hostSuccess[HostFailure](pageReply(context, stopped))

proc source(available: uint64 = high(uint64)): Machine =
  ## Two hosts followed by a genuine dynamic halt use an independent fixed instruction bitmap.
  let raw = @[0'u8, 0, 6, 10, 2, 10, 2, 50, 0, 0x15]
  let code = decodeJamProgram(raw, CodeAddress(0), ProgramByteLimit(100), JumpCountLimit(0))
  assert code.error == ProgramError.None
  let memory = captureMemory([PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)],
      PageLimit(2))
  assert memory.error == MachineError.None
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  let captured = captureMachine(code.value, memory.value,
      MachineInfo(pc: CodeAddress(0), gas: MachineGas(available), registers: registers))
  assert captured.error == MachineError.None
  captured.value

proc respond(context: var Context, stopped: StepOutcome): HostResult[HostFailure] {.raises: [].} =
  ## Read the actual causing PC and change a private immutable page before continuing.
  assert stopped.exit == StepExit.Host and uint64(stopped.hostCall) == 2
  let info = machineInfo(stopped.machine).value
  assert uint64(info.pc) == uint64(context.calls*2)
  if context.reentry:
    assert preparedInfo(context.prepared).error == PreparationError.Busy
    let nested = execute(stopped.machine, ExecutionStepLimit(1), context.prepared)
    assert nested.error == StepError.PreparedProgramBusy # The busy lease survives callback publication.
  inc context.calls
  if context.refuse: return hostFailure(HostFailure.Refused)
  let memory = memoryOf(stopped.machine).value
  let changed = store(memory, MemoryAddress(0x10000), AccessWidth(8), RegisterValue(context.calls))
  assert changed.error == MachineError.None
  var registers = info.registers
  registers[7] = RegisterValue(context.calls)
  hostSuccess[HostFailure](HostResponse(action: (if context.terminal: HostAction.Panic else: HostAction.Continue),
      gas: info.gas, gasDeficit: GasDeficit(if context.malformed: 1 else: 0),
      registers: registers, memory: changed.value))

proc run(selected: PvmBackend): HostExecutionResult[HostFailure] =
  ## Finite local policies apply to one actual host-heavy invocation.
  var context = default(Context)
  let evaluated = executeWithHost(source(), context, respond, ExecutionStepLimit(3),
      HostCallLimit(2), GasCycleLimit(1000), selected)
  assert context.calls == 2
  evaluated

proc memoryMachine(instructions: openArray[seq[byte]], memory: Memory, pc = 0'u64,
    paid = false): Machine =
  ## Independently frame short instruction bytes and marks, retaining original CPU/memory inputs.
  var code: seq[byte] = @[]
  var marks: seq[int] = @[]
  for instruction in instructions:
    marks.add(code.len)
    for octet in instruction: code.add(octet)
  assert code.len < 128
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for mark in marks: mask[mark div 8] = mask[mark div 8] or (1'u8 shl (mark mod 8))
  for octet in mask: raw.add(octet)
  let program = decodeJamProgram(raw, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0)).value
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[7] = RegisterValue(0x123456789abcdef0'u64)
  captureMachine(program, memory, MachineInfo(pc: CodeAddress(pc), gas: MachineGas(high(uint64)),
      registers: registers, blockCharged: paid)).value

proc remapReply(context: var Context, stopped: StepOutcome): HostResult[HostFailure] {.raises: [].} =
  ## A resident instance must observe host permission repair and later removal without stale mappings.
  let cpu = machineInfo(stopped.machine).value
  let memory = memoryOf(stopped.machine).value
  var page = pageImage(memory, PageIndex(16)).value
  if context.calls == 0:
    assert page.access == PageAccess.ReadOnly
    page.access = PageAccess.ReadWrite # Repair permission before the first guest store.
  else:
    assert context.calls == 1
    assert uint64(load(memory, MemoryAddress(65536), AccessWidth(8)).value) == 0x123456789abcdef0'u64
    page.access = PageAccess.Inaccessible # Retain its bytes in Nim while removing the resident mapping.
  inc context.calls
  let changed = withPage(memory, page).value
  hostSuccess[HostFailure](HostResponse(action: HostAction.Continue, gas: cpu.gas,
      registers: cpu.registers, memory: changed))

proc memoryWitness(selected: PvmBackend) =
  ## A real upstream store faults atomically, then repaired reentry preserves its paid block and all register bits.
  let empty = captureMemory([], PageLimit(2)).value
  let instructions = [@[62'u8, 7, 0, 0, 1, 0], @[58'u8, 8, 0, 0, 1, 0], @[50'u8, 0]]
  let initial = memoryMachine(instructions, empty)
  let fault = execute(initial, ExecutionStepLimit(10), GasCycleLimit(1000), selected)
  assert fault.error == StepError.None and fault.value.exit == StepExit.Fault, $selected &
      " fault attempt: " & $fault.error
  assert fault.value.backend == selected and uint32(fault.value.faultPage) == 65536
  let stopped = machineInfo(fault.value.machine).value
  assert uint64(stopped.pc) == 0 and stopped.blockCharged
  assert uint64(stopped.gas) < high(uint64)
  let repaired = withPage(memoryOf(fault.value.machine).value,
      PageImage(index: PageIndex(16), access: PageAccess.ReadWrite)).value
  let resumed = withMemory(fault.value.machine, repaired).value
  let done = execute(resumed, ExecutionStepLimit(3), GasCycleLimit(1000), selected)
  assert done.error == StepError.None and done.value.exit == StepExit.Halt, $selected &
      " repaired attempt: " & $done.error
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.gas) == uint64(stopped.gas) # Retrying a paid fault must never debit its block twice.
  assert uint64(cpu.registers[8]) == 0x123456789abcdef0'u64
  let changed = memoryOf(done.value.machine).value
  assert uint64(load(changed, MemoryAddress(65536), AccessWidth(8)).value) == 0x123456789abcdef0'u64
  assert uint64(load(repaired, MemoryAddress(65536), AccessWidth(8)).value) == 0
  assert pageImage(memoryOf(initial).value, PageIndex(16)).value.access == PageAccess.Inaccessible
  # Low protected pages may retain immutable bytes even though every guest access must panic.
  var low = PageImage(index: PageIndex(0), access: PageAccess.ReadWrite)
  low.bytes[0] = 173
  let protectedMemory = captureMemory([low], PageLimit(1)).value
  let protectedCpu = memoryMachine([@[58'u8, 8, 0], @[50'u8, 0]], protectedMemory)
  let protectedExit = execute(protectedCpu, ExecutionStepLimit(2), GasCycleLimit(1000), selected)
  assert protectedExit.error == StepError.None and protectedExit.value.exit == StepExit.Panic
  assert pageImage(memoryOf(protectedExit.value.machine).value, PageIndex(0)).value.bytes[0] == 173
  # Two actual host callbacks repair RO memory, observe a guest store, then unmap before another store faults.
  let readOnlyMemory = captureMemory([PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)],
      PageLimit(1)).value
  let remappedSource = memoryMachine([@[10'u8, 2], instructions[0], @[10'u8, 2], instructions[0], @[
      50'u8, 0]], readOnlyMemory)
  var remap = default(Context)
  let remapped = executeWithHost(remappedSource, remap, remapReply, ExecutionStepLimit(10),
      HostCallLimit(2), GasCycleLimit(1000), selected)
  assert remapped.error == HostExecutionError.None and remapped.value.exit == StepExit.Fault
  assert remap.calls == 2 and uint32(remapped.value.faultPage) == 65536
  let retained = pageImage(memoryOf(remapped.value.machine).value, PageIndex(16)).value
  assert retained.access == PageAccess.Inaccessible and retained.bytes[0] == 240
  assert pageImage(readOnlyMemory, PageIndex(16)).value.bytes[0] == 0
  # Interior reentry is explicit and independent of the paid flag, with no hidden block-start rounding.
  for paid in [false, true]:
    let interior = memoryMachine(instructions, repaired, pc = 6, paid = paid)
    let entered = execute(interior, ExecutionStepLimit(2), GasCycleLimit(1000), selected)
    if entered.error == StepError.BackendReentryUnsupported:
      assert selected == PvmBackend.PolkaCompiled # The interpreter's public arbitrary-entry path is required.
    else:
      assert entered.error == StepError.None and entered.value.exit == StepExit.Halt
      let after = machineInfo(entered.value.machine).value
      assert uint64(after.registers[8]) == 0
      if paid: assert uint64(after.gas) == high(uint64)
      else: assert uint64(after.gas) < high(uint64)
  # A missing second page precedes a read-only first page; faulted stores publish no prefix bytes.
  let readonly = captureMemory([PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)],
      PageLimit(2)).value
  let crossing = memoryMachine([@[62'u8, 7, 255, 15, 1, 0], @[50'u8, 0]], readonly)
  let crossed = execute(crossing, ExecutionStepLimit(2), GasCycleLimit(1000), selected)
  assert crossed.error == StepError.None and crossed.value.exit == StepExit.Fault, $selected &
      " crossing attempt: " & $crossed.error
  assert uint32(crossed.value.faultPage) == 69632
  assert pageImage(memoryOf(crossed.value.machine).value, PageIndex(16)).value.bytes[4095] == 0

proc witness(selected: PvmBackend) =
  ## Compare complete terminal facts, retained source isolation, independent budgets and host refusal.
  memoryWitness(selected)
  let original = source()
  let expected = run(PvmBackend.Interpreted)
  let actual = run(selected)
  assert expected.error == HostExecutionError.None and actual.error == HostExecutionError.None
  assert expected.value.exit == StepExit.Halt and actual.value.exit == StepExit.Halt
  assert actual.value.backend == selected
  let want = machineInfo(expected.value.machine).value
  let got = machineInfo(actual.value.machine).value
  assert uint64(got.pc) == uint64(want.pc) and uint64(got.gas) == uint64(want.gas)
  assert got.blockCharged == want.blockCharged
  for index in 0..<13:
    assert uint64(got.registers[index]) == uint64(want.registers[index])
  let bytes = load(memoryOf(actual.value.machine).value, MemoryAddress(0x10000), AccessWidth(8))
  assert bytes.error == MachineError.None and uint64(bytes.value) == 2
  assert load(memoryOf(original).value, MemoryAddress(0x10000), AccessWidth(8)).value.uint64 == 0
  var context = default(Context)
  let attempts = executeWithHost(original, context, respond, ExecutionStepLimit(2),
      HostCallLimit(2), GasCycleLimit(1000), selected)
  assert attempts.error == HostExecutionError.ExecutionFailure
  assert attempts.executionError == StepError.StepLimitExceeded and context.calls == 2
  context = default(Context)
  let calls = executeWithHost(original, context, respond, ExecutionStepLimit(10),
      HostCallLimit(1), GasCycleLimit(1000), selected)
  assert calls.error == HostExecutionError.ExecutionFailure
  assert calls.executionError == StepError.HostCallLimitExceeded and context.calls == 1
  context = Context(refuse: true)
  let refused = executeWithHost(original, context, respond, ExecutionStepLimit(10),
      HostCallLimit(2), GasCycleLimit(1000), selected)
  assert refused.error == HostExecutionError.HostFailure and refused.hostError ==
      HostFailure.Refused
  assert context.calls == 1
  context = Context(malformed: true)
  let malformed = executeWithHost(original, context, respond, ExecutionStepLimit(10),
      HostCallLimit(2), GasCycleLimit(1000), selected)
  assert malformed.error == HostExecutionError.ExecutionFailure
  assert malformed.executionError == StepError.InvalidHostResponse
  context = Context(terminal: true)
  let terminal = executeWithHost(original, context, respond, ExecutionStepLimit(10),
      HostCallLimit(2), GasCycleLimit(1000), selected)
  assert terminal.error == HostExecutionError.None and terminal.value.exit == StepExit.Panic
  assert terminal.value.backend == selected and context.calls == 1
  # Adjacent identical host IDs do not authorize replacing the genuine causing PC.
  let suspended = execute(original, ExecutionStepLimit(1), GasCycleLimit(1000), selected).value
  var forged = suspended
  var wrong = machineInfo(suspended.machine).value
  wrong.pc = CodeAddress(2)
  forged.machine = captureTerminalMachine(programOf(suspended.machine).value,
      memoryOf(suspended.machine).value, wrong).value
  let reply = HostResponse(action: HostAction.Continue, gas: wrong.gas,
      registers: wrong.registers, memory: memoryOf(suspended.machine).value)
  assert applyHostResponse(forged, reply).error == StepError.InvalidHostSuspension
  let zero = execute(source(0), ExecutionStepLimit(1), GasCycleLimit(1000), selected)
  assert zero.error == StepError.None and zero.value.exit == StepExit.OutOfGas
  assert uint64(machineInfo(zero.value.machine).value.gas) == 0

proc preparedPageReplyWitness(selected: PvmBackend) =
  ## Every host action obeys the owner's page ceiling; rejection releases the lease and resets foreign state.
  let original = source()
  var limits = defaultPreparedLimits(GasCycleLimit(1000))
  limits.resources.pages = PageLimit(1)
  let prepared = newPreparedProgram(programOf(original).value, limits, selected)
  assert prepared.error == PreparationError.None
  let bounded = memoryOf(original).value
  let oversized = captureMemory([
    PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)], PageLimit(2)).value
  for action in [HostAction.Continue, HostAction.Panic, HostAction.OutOfGas]:
    # The exact admitted ceiling stays valid for both callback interfaces and all accepted actions.
    let expected = if action == HostAction.Continue: StepExit.Halt
      elif action == HostAction.Panic: StepExit.Panic else: StepExit.OutOfGas
    for fallible in [false, true]:
      var allowed = PageReplyContext(action: action, memory: bounded)
      var rejected = PageReplyContext(action: action, memory: oversized)
      if fallible:
        let accepted = executeWithHost(original, allowed, falliblePageReply, ExecutionStepLimit(3),
            HostCallLimit(2), prepared.value)
        assert accepted.error == HostExecutionError.None and accepted.value.exit == expected
        let refused = executeWithHost(original, rejected, falliblePageReply, ExecutionStepLimit(3),
            HostCallLimit(2), prepared.value)
        assert refused.error == HostExecutionError.ExecutionFailure
        assert refused.executionError == StepError.InvalidHostResponse, $selected & " oversized fallible reply"
      else:
        let accepted = executeWithHost(original, allowed, pageReply, ExecutionStepLimit(3),
            HostCallLimit(2), prepared.value)
        assert accepted.error == StepError.None and accepted.value.exit == expected
        let refused = executeWithHost(original, rejected, pageReply, ExecutionStepLimit(3),
            HostCallLimit(2), prepared.value)
        assert refused.error == StepError.InvalidHostResponse, $selected & " oversized direct reply"
      assert rejected.calls == 1
      # A refused reply cannot poison the reusable instance, busy lease or immutable caller snapshot.
      var recovered = default(Context)
      let reused = executeWithHost(original, recovered, respond, ExecutionStepLimit(3),
          HostCallLimit(2), prepared.value)
      assert reused.error == HostExecutionError.None and reused.value.exit == StepExit.Halt
      assert recovered.calls == 2
      assert uint64(load(memoryOf(reused.value.machine).value, MemoryAddress(65536), AccessWidth(
          8)).value) == 2
      assert uint64(load(bounded, MemoryAddress(65536), AccessWidth(8)).value) == 0

proc preparedWitness(selected: PvmBackend) =
  ## Reuse one engine-bound source cache while every call resets RAM, registers and continuation.
  let original = source()
  let owner = programOf(original).value
  let prepared = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(1000)), selected)
  assert prepared.error == PreparationError.None
  assert preparedInfo(prepared.value).value.backend == selected
  assert programOf(prepared.value).value == owner
  for invocation in 0..<3:
    var context = Context(prepared: prepared.value, reentry: true)
    let answer = executeWithHost(original, context, respond, ExecutionStepLimit(3), HostCallLimit(
        2), prepared.value)
    assert answer.error == HostExecutionError.None and answer.value.exit == StepExit.Halt
    assert answer.value.backend == selected and context.calls == 2
    let changed = memoryOf(answer.value.machine).value
    assert uint64(load(changed, MemoryAddress(65536), AccessWidth(8)).value) == 2
    assert uint64(load(memoryOf(original).value, MemoryAddress(65536), AccessWidth(8)).value) == 0
  let mismatch = execute(source(), ExecutionStepLimit(3), prepared.value)
  assert mismatch.error == StepError.InvalidPreparedProgram # Identical bytes do not confer source identity.

preparedPageReplyWitness(PvmBackend.Interpreted)
preparedWitness(PvmBackend.Interpreted)
witness(PvmBackend.Interpreted)
for attempt in 0..<3:
  # The new public policy never publishes a prepared owner or substitutes any engine after its source hook refuses.
  let initial = source()
  let code = programOf(initial).value
  let unavailable = newPreparedProgram(code, defaultPreparedLimits(), PvmBackend.Compiled)
  assert unavailable.error == PreparationError.BackendNotBuilt
  assert execute(initial, ExecutionStepLimit(3), GasCycleLimit(1000),
      PvmBackend.Compiled).error == StepError.BackendNotBuilt
  var blocked = default(Context)
  let refused = executeWithHost(initial, blocked, respond, ExecutionStepLimit(3),
      HostCallLimit(2), GasCycleLimit(1000), PvmBackend.Compiled)
  assert refused.error == HostExecutionError.ExecutionFailure and
      refused.executionError == StepError.BackendNotBuilt and blocked.calls == 0
  var direct = PageReplyContext(action: HostAction.Continue, memory: memoryOf(initial).value)
  let directRefusal = executeWithHost(initial, direct, pageReply, ExecutionStepLimit(3),
      HostCallLimit(2), GasCycleLimit(1000), PvmBackend.Compiled)
  assert directRefusal.error == StepError.BackendNotBuilt and direct.calls == 0
  assert uint64(machineInfo(initial).value.gas) == high(uint64)
  assert uint64(load(memoryOf(initial).value, MemoryAddress(65536), AccessWidth(8)).value) == 0
assert backendAvailability(PvmBackend.Compiled) == StepError.BackendNotBuilt
assert newPreparedProgram(default(Program), defaultPreparedLimits(), PvmBackend.Compiled).error ==
    PreparationError.InvalidProgram
var tight = defaultPreparedLimits()
tight.resources.codeBytes = ProgramByteLimit(0)
assert newPreparedProgram(programOf(source()).value, tight, PvmBackend.Compiled).error ==
    PreparationError.LimitExceeded
let paperCompiled = decodeProgram(@[0'u8, 0, 2, 50, 0, 1], CodeAddress(0), ProgramByteLimit(64),
    JumpCountLimit(0))
assert paperCompiled.error == ProgramError.None
assert newPreparedProgram(paperCompiled.value, defaultPreparedLimits(),
    PvmBackend.Compiled).error ==

PreparationError.BackendNotBuilt # The independent identity cannot enter the foreign-only JAM profile gate.
when defined(polkavmRuntime):
  try:
    # Raw paper and the scoped JAM profile have different accepted jump-table semantics; never reinterpret one silently.
    let paper = decodeProgram(@[0'u8, 0, 2, 50, 0, 1], CodeAddress(0), ProgramByteLimit(64),
        JumpCountLimit(0)).value
    let model = source()
    let raw = captureMachine(paper, memoryOf(model).value, machineInfo(model).value).value
    let refusedProfile = execute(raw, ExecutionStepLimit(10), GasCycleLimit(1000),
        PvmBackend.PolkaInterpreted)
    assert refusedProfile.error == StepError.BackendProgramUnsupported
    let previousBackend = getEnv("POLKAVM_BACKEND")
    putEnv("POLKAVM_BACKEND", "compiler")
    # An enabled/conflicting foreign runtime cannot absorb the independent unavailable policy.
    let independentUnavailable = newPreparedProgram(programOf(source()).value,
        defaultPreparedLimits(), PvmBackend.Compiled)
    assert independentUnavailable.error == PreparationError.BackendNotBuilt
    preparedPageReplyWitness(PvmBackend.PolkaInterpreted)
    preparedWitness(PvmBackend.PolkaInterpreted)
    witness(PvmBackend.PolkaInterpreted) # Even a conflicting environment cannot choose the engine.
    # Compiled execution remains an explicit API/CLI capability; CI uses PolkaVM interpreted only.
    if previousBackend.len == 0: delEnv("POLKAVM_BACKEND")
    else: putEnv("POLKAVM_BACKEND", previousBackend)
  except:
    assert false, "test environment update failed"
else:
  for selected in [PvmBackend.PolkaInterpreted, PvmBackend.PolkaCompiled]:
    let refused = execute(source(), ExecutionStepLimit(10), GasCycleLimit(1000), selected)
    assert refused.error == StepError.BackendNotBuilt
stdout.writeLine("PASS runtime PVM backends")
