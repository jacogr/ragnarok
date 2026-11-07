# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit scalar callbacks preserve accumulated dirty bytes, retained owned epochs and shared budgets.
## Authored mixed programs exercise the public driver and stopped-frame refusal/retry boundary.
# @@Verification={"arc": "pvm_scalar_host_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/handler_stream
import ../../support/arc_evidence

type
  Mode {.pure.} = enum ## Each refusal or terminal outcome is selected before a callback returns.
    Normal, Panic, OutOfGas, Refused, InvalidAction, InvalidDeficit, Malformed
  Refusal {.pure.} = enum ## Zero is a genuine local refusal, not an implicit success ordinal.
    Rejected
  Context = object ## Only owned snapshots and copied CPU values may outlive callback delivery.
    calls, scalars, owned: int
    mode: Mode
    roots: seq[Machine]
    cpus: seq[MachineInfo]

proc owner(parts: openArray[seq[byte]]): Program =
  ## Assemble bounded literal instructions; this fixture frames bytes but never replaces a decoder/verdict.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # Every operand remains unmarked, including bytes equal to valid opcodes.
    assert part.len > 0
    starts.add(code.len)
    for octet in part: code.add(octet)
  assert code.len > 0 and code.len < 128
  var wire = @[0'u8, 0, byte(code.len)]
  for octet in code: wire.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for pc in starts: mask[pc div 8] = mask[pc div 8] or (1'u8 shl (pc mod 8))
  for octet in mask: wire.add(octet)
  decodeProgram(wire, CodeAddress(0), ProgramByteLimit(128), JumpCountLimit(0)).value

proc storeByte(address: uint32, value: byte): seq[byte] =
  ## A literal three-byte absolute address and one-byte immediate select a checked byte store.
  assert address >= 65536 and address < 0x800000 and value < 128
  @[30'u8, 3, byte(address and 255), byte((address shr 8) and 255),
    byte((address shr 16) and 255), value]

proc mixedProgram(): Program =
  ## Exact PCs are 0/store,6/7,8/9,10/8,12/store,18/7,20/store,26/8,28/halt.
  owner([storeByte(65536, 11), @[10'u8, 7], @[10'u8, 9], @[10'u8, 8],
    storeByte(65536, 33), @[10'u8, 7], storeByte(65538, 44), @[10'u8, 8], @[50'u8, 0]])

proc initialMemory(): Memory =
  ## Two immutable pages carry complete canaries, including bytes never touched by this guest.
  var pages = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)]
  for page in 0..<2:
    for at in 0..<4096: pages[page].bytes[at] = 0x65
  captureMemory(pages, PageLimit(2)).value

proc initial(source: Program, memory: Memory): Machine =
  ## Prepaid gas isolates exact host posterior changes while preserving the genuine continuation flag.
  var registers = default(RegisterFile)
  for index in 0..<13: registers[index] = RegisterValue(1000+uint64(index))
  registers[0] = RegisterValue(0xffff0000'u64)
  captureMachine(source, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(100000),
    blockCharged: true, registers: registers)).value

func scalarCalls(call: HostCallId): bool =
  ## A pure pre-callback selector declares the two copied-CPU calls; id8 requires an owned observation.
  uint64(call) in [7'u64, 9'u64]

proc scalarReply(context: var Context, call: HostCallId,
    cpu: MachineInfo): ScalarHostResponse {.raises: [].} =
  ## Scalar delivery has no memory handle, and copied CPU values remain independent after later replies.
  assert scalarCalls(call) and cpu.blockCharged
  let pc = [6'u64, 8, 10, 18, 26][context.calls]
  assert uint64(cpu.pc) == pc and uint64(cpu.gas) == 100000-uint64(context.calls)
  context.cpus.add(cpu)
  inc context.calls
  inc context.scalars
  var registers = cpu.registers
  registers[8] = RegisterValue(uint64(context.calls))
  result = ScalarHostResponse(action: HostAction.Continue, gas: MachineGas(uint64(cpu.gas)-1),
    gasDeficit: GasDeficit(0), registers: registers)
  case context.mode
  of Mode.Panic:
    result.action = HostAction.Panic # A terminal response must publish the preceding guest store.
  of Mode.OutOfGas:
    result.action = HostAction.OutOfGas
    result.gas = MachineGas(0)
  of Mode.InvalidAction:
    result.action = HostAction.Halt # The excluded action cannot resume or publish partial state.
  of Mode.InvalidDeficit:
    result.gasDeficit = GasDeficit(1)
  else:
    discard # Typed refusal and malformed selection are exercised by the fallible wrapper.

proc ownedReply(context: var Context, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## The owned fallback may retain the observation and return independently changed posterior bytes.
  let cpu = machineInfo(stopped.machine).value
  let memory = memoryOf(stopped.machine).value
  if scalarCalls(stopped.hostCall):
    # The legacy control shares protocol arithmetic but still receives its original owned capability.
    let reply = scalarReply(context, stopped.hostCall, cpu)
    return HostResponse(action: reply.action, gas: reply.gas, gasDeficit: reply.gasDeficit,
      registers: reply.registers, memory: memory)
  assert uint64(stopped.hostCall) == 8 and context.calls in [2, 4]
  let first = context.calls == 2
  assert uint64(cpu.pc) == (if first: 10'u64 else: 26'u64)
  assert uint64(cpu.gas) == 100000-uint64(context.calls)
  assert uint64(load(memory, MemoryAddress(65536), AccessWidth(1)).value) ==
    (if first: 11'u64 else: 33'u64)
  if not first:
    # Guest dirties since the first owned epoch must survive another scalar callback.
    assert uint64(load(memory, MemoryAddress(65537), AccessWidth(1)).value) == 22
    assert uint64(load(memory, MemoryAddress(65538), AccessWidth(1)).value) == 44
  context.roots.add(stopped.machine)
  inc context.calls
  inc context.owned
  var registers = cpu.registers
  registers[8] = RegisterValue(uint64(context.calls))
  let changed = store(memory, MemoryAddress(65537), AccessWidth(1),
    RegisterValue(if first: 22'u64 else: 55'u64)).value
  HostResponse(action: HostAction.Continue, gas: MachineGas(uint64(cpu.gas)-1),
    gasDeficit: GasDeficit(0), registers: registers, memory: changed)

proc fallibleOwned(context: var Context, stopped: StepOutcome): HostResult[Refusal]
    {.raises: [].} =
  ## The typed route keeps the same owned fallback and its retained snapshots.
  hostSuccess[Refusal](ownedReply(context, stopped))

proc fallibleScalar(context: var Context, call: HostCallId,
    cpu: MachineInfo): ScalarHostResult[Refusal] {.raises: [].} =
  ## Effects already performed in context survive local refusal, while no engine posterior is exposed.
  let reply = scalarReply(context, call, cpu)
  case context.mode
  of Mode.Refused:
    scalarHostFailure(Refusal.Rejected)
  of Mode.Malformed:
    default(ScalarHostResult[Refusal])
  else:
    scalarHostSuccess[Refusal](reply)

proc checkMemory(memory: Memory, first, second, third: byte) =
  ## Full two-page equality catches missing dirty pages and accidental writes outside the three authored bytes.
  for page in 0..<2:
    let image = pageImage(memory, PageIndex(uint32(16+page))).value
    assert image.access == PageAccess.ReadWrite
    for at in 0..<4096:
      let expected = if page == 0 and at == 0: first
        elif page == 0 and at == 1: second
        elif page == 0 and at == 2: third else: 0x65'u8
      assert image.bytes[at] == expected

proc mixedCycle() =
  ## One typed and one response-only invocation preserve independent earlier snapshots and the original input.
  let code = mixedProgram()
  let memory = initialMemory()
  let source = initial(code, memory)
  let prepared = newPreparedProgram(code, defaultPreparedLimits(GasCycleLimit(1000)),
    PvmBackend.Interpreted).value
  var context = Context(mode: Mode.Normal, roots: @[], cpus: @[])
  let done = executeWithHost(source, context, ownedReply, ExecutionStepLimit(9),
    HostCallLimit(5), prepared, scalarCalls, scalarReply)
  assert done.error == StepError.None and done.value.exit == StepExit.Halt
  assert context.calls == 5 and context.scalars == 3 and context.owned == 2
  let cpu = machineInfo(done.value.machine).value
  assert uint64(cpu.pc) == 0 and uint64(cpu.gas) == 99995 and uint64(cpu.gasDeficit) == 0
  let input = machineInfo(source).value
  for index in 0..<13:
    # Only r8 belongs to the authored callbacks; every unrelated register keeps its complete value.
    let expected = if index == 8: 5'u64 else: uint64(input.registers[index])
    assert uint64(cpu.registers[index]) == expected
  checkMemory(memoryOf(done.value.machine).value, 33, 55, 44)
  checkMemory(memoryOf(context.roots[0]).value, 11, 0x65, 0x65)
  checkMemory(memoryOf(context.roots[1]).value, 33, 22, 44)
  for index in 0..<context.roots.len:
    # Full owned CPU observations remain at their original delivery instant after later replies.
    let held = machineInfo(context.roots[index]).value
    assert uint64(held.pc) == [10'u64, 26][index]
    assert uint64(held.gas) == [99998'u64, 99996][index]
    assert uint64(held.registers[8]) == [2'u64, 4][index]
  checkMemory(memory, 0x65, 0x65, 0x65)
  for index in 0..<context.cpus.len:
    # Retained scalar observations describe their delivery instant rather than later CPU mutation.
    assert uint64(context.cpus[index].pc) == [6'u64, 8, 18][index]
  var typed = Context(mode: Mode.Normal, roots: @[], cpus: @[])
  let repeated = executeWithHost(source, typed, fallibleOwned, ExecutionStepLimit(9),
    HostCallLimit(5), prepared, scalarCalls, fallibleScalar)
  assert repeated.error == HostExecutionError.None
  assert machineInfo(repeated.value.machine).value == cpu
  checkMemory(memoryOf(repeated.value.machine).value, 33, 55, 44)
  var legacy = Context(mode: Mode.Normal, roots: @[], cpus: @[])
  let owned = executeWithHost(source, legacy, ownedReply, ExecutionStepLimit(9),
    HostCallLimit(5), prepared)
  assert owned.error == StepError.None and machineInfo(owned.value.machine).value == cpu
  checkMemory(memoryOf(owned.value.machine).value, 33, 55, 44)

block terminalsAndRefusals:
  let code = mixedProgram()
  let source = initial(code, initialMemory())
  let prepared = newPreparedProgram(code, defaultPreparedLimits(), PvmBackend.Interpreted).value
  for mode in [Mode.Panic, Mode.OutOfGas, Mode.Refused, Mode.InvalidAction,
      Mode.InvalidDeficit, Mode.Malformed]:
    # The first callback uses the final allowed guest attempt; a terminal reply still completes.
    var context = Context(mode: mode, roots: @[], cpus: @[])
    let done = executeWithHost(source, context, fallibleOwned, ExecutionStepLimit(2),
      HostCallLimit(1), prepared, scalarCalls, fallibleScalar)
    assert context.calls == 1 and context.scalars == 1 and context.owned == 0
    if mode in [Mode.Panic, Mode.OutOfGas]:
      assert done.error == HostExecutionError.None
      assert done.value.exit == (if mode == Mode.Panic: StepExit.Panic else: StepExit.OutOfGas)
      assert uint64(machineInfo(done.value.machine).value.pc) == 6
      checkMemory(memoryOf(done.value.machine).value, 11, 0x65, 0x65)
    elif mode == Mode.Refused:
      assert done.error == HostExecutionError.HostFailure and done.hostError == Refusal.Rejected
    else:
      assert done.error == HostExecutionError.ExecutionFailure
      assert done.executionError == StepError.InvalidHostResponse
    checkMemory(memoryOf(source).value, 0x65, 0x65, 0x65)

block exactBudgets:
  let code = mixedProgram()
  let source = initial(code, initialMemory())
  let prepared = newPreparedProgram(code, defaultPreparedLimits(), PvmBackend.Interpreted).value
  for steps in 0'u64..9'u64:
    # Host instructions occupy attempts2,3,4,6,8; scalar delivery cannot replenish the total.
    var context = Context(mode: Mode.Normal, roots: @[], cpus: @[])
    let done = executeWithHost(source, context, ownedReply, ExecutionStepLimit(steps),
      HostCallLimit(5), prepared, scalarCalls, scalarReply)
    var expected = 0
    for attempt in [2'u64, 3, 4, 6, 8]:
      if attempt <= steps: inc expected
    assert context.calls == expected
    assert done.error == (if steps == 9: StepError.None else: StepError.StepLimitExceeded)
  for calls in 0'u64..5'u64:
    # Exhaustion happens before the next capability is observed or either callback executes.
    var context = Context(mode: Mode.Normal, roots: @[], cpus: @[])
    let done = executeWithHost(source, context, ownedReply, ExecutionStepLimit(9),
      HostCallLimit(calls), prepared, scalarCalls, scalarReply)
    assert context.calls == int(calls)
    assert done.error == (if calls == 5: StepError.None else: StepError.HostCallLimitExceeded)

block ownedReplacementRetry:
  let code = mixedProgram()
  let memory = initialMemory()
  let source = initial(code, memory)
  var limits = defaultFlatLimits()
  limits.pages = PageLimit(2)
  var admitted = prepareFlatPlan(code, GasCycleLimit(1000), limits, false)
  let plan = takeValue(admitted)
  var built = prepareFlatMemoryFrame(plan, memory, machineInfo(source).value)
  var frame = takeValue(built)
  runFlat(frame, 2)
  assert frame.exit == StepExit.Host
  let stopped = frame.info # Copy only POD CPU values before borrowing the exclusive frame mutably.
  assert resumeFlatHostScalars(frame, stopped.gas, stopped.registers) ==
    StepError.InvalidHostSuspension
  for next in 0..<2:
    # Both scalar continuations leave the first guest store dirty against the original baseline.
    let cpu = observeFlatHostScalars(frame)
    assert resumeFlatHostScalars(frame, cpu.gas, cpu.registers) == StepError.None
    runFlat(frame, 1)
  assert uint64(frame.info.pc) == 10
  let observed = observeFlatHostMemory(frame)
  checkMemory(observed, 11, 0x65, 0x65)
  let before = frame.info
  let oversized = captureMemory([PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(17), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(18), access: PageAccess.ReadWrite)], PageLimit(3)).value
  assert resumeFlatHostMemory(frame, oversized, before.gas, before.registers) ==
    StepError.InvalidHostResponse
  assert frame.info == before
  checkMemory(flatMemorySnapshot(frame), 11, 0x65, 0x65)
  let posterior = store(observed, MemoryAddress(65537), AccessWidth(1), RegisterValue(22)).value
  assert resumeFlatHostMemory(frame, posterior, before.gas, before.registers) == StepError.None
  runFlat(frame, 2)
  let cpu = observeFlatHostScalars(frame)
  assert resumeFlatHostScalars(frame, cpu.gas, cpu.registers) == StepError.None
  runFlat(frame, 2)
  let second = observeFlatHostMemory(frame)
  checkMemory(second, 33, 22, 44)
  checkMemory(observed, 11, 0x65, 0x65)

mixedCycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Drop complete prepared/scratch/context/retained-epoch graphs before the next fresh ownership cycle.
  mixedCycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_scalar_host", 1000, before, after)
echo "PVM scalar host mixed-mode and retention checks passed"
echo "ARC_RELEASE cycles=1000 unchanged"
