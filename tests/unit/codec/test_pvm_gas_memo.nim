# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent gas prices, complete execution parity, policy ownership, host replies and paid retries.
# @@Verification={"arc": "pvm_gas_memo_arc_release"}
import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/[gas, memo as gas_memo]
import ../../../src/pvm/step
import ../../support/arc_evidence

proc limits(): GasMemoLimits =
  ## Explicit generous test policy remains distinct from guest gas and every source's byte limits.
  GasMemoLimits(bytes: GasMemoByteLimit(8*1024*1024),
    cycles: GasCycleLimit(1000000))
proc code(parts: openArray[seq[byte]]): Program =
  ## Independently frame short original instruction partitions with explicit marker bytes.
  var bytes: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(bytes.len)
    for octet in part: bytes.add(octet)
  assert bytes.len > 0 and bytes.len < 128
  var wire = @[0'u8, 0, byte(bytes.len)]
  for octet in bytes: wire.add(octet)
  var mask = newSeq[byte]((bytes.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for octet in mask: wire.add(octet)
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(256), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  decoded.value
proc input(owner: Program, fuel: uint64, memory: Memory, pc = CodeAddress(0)): Machine =
  ## Own copied CPU sentinels and immutable children; no prepared memo can choose guest state.
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  captureMachine(owner, memory, MachineInfo(pc: pc, gas: MachineGas(fuel),
    gasDeficit: GasDeficit(0), blockCharged: false, registers: registers)).value
proc same(left, right: StepResult) =
  ## Compare every CPU/outcome field and the unchanged empty-memory owner for corpus first steps.
  assert left.error == right.error
  if left.error == StepError.None:
    let a = left.value
    let b = right.value
    assert a.exit == b.exit
    let x = machineInfo(a.machine).value
    let y = machineInfo(b.machine).value
    assert uint64(x.pc) == uint64(y.pc) and uint64(x.gas) == uint64(y.gas)
    assert uint64(x.gasDeficit) == uint64(y.gasDeficit) and x.blockCharged == y.blockCharged
    for i in 0..<13: assert uint64(x.registers[i]) == uint64(y.registers[i])
    assert memoryOf(a.machine).value == memoryOf(b.machine).value
    if a.exit == StepExit.Fault:
      assert b.exit == StepExit.Fault
      assert uint32(a.faultPage) == uint32(b.faultPage)
    elif a.exit == StepExit.Host:
      assert b.exit == StepExit.Host
      assert uint64(a.hostCall) == uint64(b.hostCall)
proc word(data: string, at, width: int): uint64 =
  ## Parse only fixed fixture fields after their containing record extent is established.
  assert at >= 0 and width in 1..8 and at <= data.len-width
  result = 0
  for i in 0..<width: result = result or (uint64(byte(data[at+i])) shl (8*i))

let empty = captureMemory([], PageLimit(0)).value
var data = ""
try:
  data = readFile(getEnv("RAGNAROK_PVM_GAS"))
except:
  quit 2 # Missing independent corpus bytes cannot become an omitted parity check.
assert data.len >= 12 and data[0..7] == "PVMGAS01"
let count = int(word(data, 8, 4))
assert count >= 1796
var cursor = 12
for row in 0..<count:
  assert cursor <= data.len-24
  let start = CodeAddress(word(data, cursor, 4))
  let expected = word(data, cursor+4, 8)
  let cycles = word(data, cursor+12, 8)
  let length = int(word(data, cursor+20, 4))
  cursor += 24
  assert length > 0 and length <= data.len-cursor
  var wire = newSeq[byte](length)
  for i in 0..<length: wire[i] = byte(data[cursor+i])
  cursor += length
  let captured = decodeProgram(wire, start, ProgramByteLimit(uint64(length)), JumpCountLimit(0))
  assert captured.error == ProgramError.None
  let owner = captured.value
  let created = newGasMemo(owner, limits())
  assert created.error == GasMemoError.None
  let memo = created.value
  assert gasMemoInfo(memo).value.pricedBlocks == 0
  assert uint64(blockGas(memo, start).value) == expected
  assert matchesProgram(memo, owner) and programOf(memo).value == owner
  let size = gasMemoInfo(memo).value
  assert size.codeBytes == codeLength(owner).value and size.payloadBytes == size.codeBytes*8
  assert uint64(size.cycleLimit) == 1000000 and size.pricedBlocks == 1
  for fuel in [0'u64, expected-1, expected]:
    # Exact independent prices protect affordability boundaries; bounded execution retains its prior verdict/state.
    let source = input(owner, fuel, empty, start)
    same(execute(source, ExecutionStepLimit(1), GasCycleLimit(1000000)),
      execute(source, ExecutionStepLimit(1), memo))
    assert uint64(machineInfo(source).value.gas) == fuel and not machineInfo(
        source).value.blockCharged
  var short = limits()
  short.cycles = GasCycleLimit(cycles-1)
  let refused = newGasMemo(owner, short)
  assert refused.error == GasMemoError.None
  assert blockGas(refused.value, start).error == GasMemoError.CycleLimitExceeded
  assert gasMemoInfo(refused.value).value.pricedBlocks == 0
assert cursor == data.len

let main = code([@[10'u8], @[131'u8, 119, 1], @[10'u8], @[131'u8, 119, 1], @[50'u8, 0]])
let price = uint64(blockGas(main, CodeAddress(0), GasCycleLimit(1000000)).value)
let source = input(main, price+7, empty)
let memo = newGasMemo(main, limits()).value
assert gasMemoInfo(memo).value.pricedBlocks == 0
assert blockGas(memo, CodeAddress(1)).error == GasMemoError.InvalidStart
assert gasMemoInfo(memo).value.pricedBlocks == 0
assert blockGas(memo, CodeAddress(2)).error == GasMemoError.InvalidStart
assert blockGas(memo, CodeAddress(high(uint64))).error == GasMemoError.InvalidStart
assert blockGas(default(GasMemo), CodeAddress(0)).error == GasMemoError.InvalidProgram
assert newGasMemo(default(Program), limits()).error == GasMemoError.InvalidProgram
var exact = limits()
exact.bytes = GasMemoByteLimit(gasMemoInfo(memo).value.payloadBytes)
assert newGasMemo(main, exact).error == GasMemoError.None
exact.bytes = GasMemoByteLimit(uint64(exact.bytes)-1)
assert newGasMemo(main, exact).error == GasMemoError.LimitExceeded
exact = limits()
exact.cycles = GasCycleLimit(0)
let zeroCycle = newGasMemo(main, exact)
assert zeroCycle.error == GasMemoError.None
assert blockGas(zeroCycle.value, CodeAddress(0)).error == GasMemoError.CycleLimitExceeded
assert gasMemoInfo(zeroCycle.value).value.pricedBlocks == 0
assert execute(source, ExecutionStepLimit(1), zeroCycle.value).error ==
    StepError.GasCycleLimitExceeded
let paidHost = stepOnce(source, GasCycleLimit(1000000)).value.machine
same(execute(paidHost, ExecutionStepLimit(1), GasCycleLimit(0)),
  execute(paidHost, ExecutionStepLimit(1), zeroCycle.value))
assert newGasMemo(main, default(GasMemoLimits)).error == GasMemoError.LimitExceeded
let other = code([@[0'u8]])
let otherMemo = newGasMemo(other, limits()).value
assert not matchesProgram(memo, other) and not matchesProgram(default(GasMemo), main)
assert execute(input(other, 1000, empty), ExecutionStepLimit(1), memo).error ==
    StepError.InvalidGasMemo
assert execute(source, ExecutionStepLimit(0), default(GasMemo)).error == StepError.InvalidGasMemo
assert execute(source, ExecutionStepLimit(1), otherMemo).error == StepError.InvalidGasMemo
var observation = gasMemoInfo(memo).value
observation.cycleLimit = GasCycleLimit(0)
assert uint64(gasMemoInfo(memo).value.cycleLimit) == 1000000

# A separately captured identical wire still has a distinct immutable identity, including decode profile.
let equivalent = code([@[10'u8], @[131'u8, 119, 1], @[10'u8], @[131'u8, 119, 1], @[50'u8, 0]])
assert not matchesProgram(memo, equivalent)
assert execute(input(equivalent, price+7, empty), ExecutionStepLimit(5), memo).error ==
    StepError.InvalidGasMemo

type
  Reason = enum ## The zero ordinal remains a genuine callback refusal, never an implied success.
    Refused
  Context = object ## Mutable callback state may replace its original sole memo handle during a synchronous invocation.
    calls: int
    memo, replacement: GasMemo
    nestedSource: Machine
    nested, drop, refuse: bool
proc context(source: Machine, memo: GasMemo): Context =
  ## Explicitly initialize every flag and retain only caller-owned immutable handles.
  Context(calls: 0, memo: memo, replacement: default(GasMemo), nestedSource: source,
    nested: false, drop: false, refuse: false)
proc effects(ctx: var Context) {.raises: [].} =
  ## Nested guest-only execution and context replacement must not disturb the outer immutable pricing policy.
  inc ctx.calls
  if ctx.nested and ctx.calls == 1:
    let nested = execute(ctx.nestedSource, ExecutionStepLimit(1), ctx.memo)
    assert nested.error == StepError.None and nested.value.exit == StepExit.Host
  if ctx.drop and ctx.calls == 1: ctx.memo = ctx.replacement
proc reply(suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Return only the host-permitted posterior fields; code, PC and charged state stay engine-owned.
  let cpu = machineInfo(suspension.machine).value
  var registers = cpu.registers
  registers[7] = RegisterValue(uint64(registers[7])+10)
  HostResponse(action: HostAction.Continue, gas: cpu.gas, gasDeficit: GasDeficit(0),
    registers: registers, memory: memoryOf(suspension.machine).value)
proc respond(ctx: var Context, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Response-only callers exercise the same scheduler and budget boundaries as fallible handlers.
  effects(ctx)
  reply(suspension)
proc fallible(ctx: var Context, suspension: StepOutcome): HostResult[Reason] {.raises: [].} =
  ## Refuse before applying a second response while preserving already-performed caller side effects.
  effects(ctx)
  if ctx.refuse and ctx.calls == 2: return hostFailure(Reason.Refused)
  hostSuccess[Reason](reply(suspension))
for attempts in [0'u64, 1, 4, 5]:
  for dispatches in [0'u64, 1, 2]:
    var ordinary = context(source, memo)
    var planned = context(source, memo)
    let a = executeWithHost(source, ordinary, respond, ExecutionStepLimit(attempts),
      HostCallLimit(dispatches), GasCycleLimit(1000000))
    let b = executeWithHost(source, planned, respond, ExecutionStepLimit(attempts),
      HostCallLimit(dispatches), memo)
    same(a, b)
    assert ordinary.calls == planned.calls
# Interior executable entry resolves the containing full block; planned pricing never treats an operand as a start.
for fuel in [0'u64, price-1, price]:
  let interior = input(main, fuel, empty, CodeAddress(1))
  same(execute(interior, ExecutionStepLimit(4), GasCycleLimit(1000000)),
    execute(interior, ExecutionStepLimit(4), memo))
# A foreign or absent policy refuses before either callback can observe a suspension.
for wrong in [otherMemo, default(GasMemo)]:
  var plain = context(source, memo)
  let rejected = executeWithHost(source, plain, respond, ExecutionStepLimit(5), HostCallLimit(2), wrong)
  assert rejected.error == StepError.InvalidGasMemo and plain.calls == 0
  var fallibleContext = context(source, memo)
  let refused = executeWithHost(source, fallibleContext, fallible, ExecutionStepLimit(5),
      HostCallLimit(2), wrong)
  assert refused.error == HostExecutionError.ExecutionFailure
  assert refused.executionError == StepError.InvalidGasMemo and fallibleContext.calls == 0
var ordinaryFailure = context(source, memo)
var plannedFailure = context(source, memo)
ordinaryFailure.refuse = true
plannedFailure.refuse = true
let refusedA = executeWithHost(source, ordinaryFailure, fallible, ExecutionStepLimit(5),
  HostCallLimit(2), GasCycleLimit(1000000))
let refusedB = executeWithHost(source, plannedFailure, fallible, ExecutionStepLimit(5),
    HostCallLimit(2), memo)
assert refusedA.error == HostExecutionError.HostFailure and refusedB.error ==
    HostExecutionError.HostFailure
assert refusedA.hostError == Reason.Refused and refusedB.hostError == Reason.Refused
assert ordinaryFailure.calls == 2 and plannedFailure.calls == 2
var nested = context(source, memo)
nested.nested = true
let completed = executeWithHost(source, nested, respond, ExecutionStepLimit(5), HostCallLimit(2), memo)
assert completed.error == StepError.None and completed.value.exit == StepExit.Halt and
    nested.calls == 2
assert uint64(machineInfo(completed.value.machine).value.registers[7]) == 22
assert uint64(machineInfo(completed.value.machine).value.gas) == 7
# Copy the policy value before exclusively borrowing its supplying context; direct field aliasing is rejected by the compiler.
var dropping = context(source, newGasMemo(main, limits()).value)
dropping.drop = true
dropping.replacement = otherMemo
let supplied = dropping.memo
let dropped = executeWithHost(source, dropping, respond, ExecutionStepLimit(5), HostCallLimit(2), supplied)
assert dropped.error == StepError.None and dropped.value.exit == StepExit.Halt and dropping.calls == 2
assert matchesProgram(dropping.memo, other)
var droppingFallible = context(source, newGasMemo(main, limits()).value)
droppingFallible.drop = true
droppingFallible.replacement = otherMemo
let suppliedFallible = droppingFallible.memo
let droppedFallible = executeWithHost(source, droppingFallible, fallible, ExecutionStepLimit(5),
  HostCallLimit(2), suppliedFallible)
assert droppedFallible.error == HostExecutionError.None and droppedFallible.value.exit == StepExit.Halt
assert uint64(machineInfo(source).value.gas) == price+7 and uint64(machineInfo(
    source).value.registers[7]) == 0

# A matching memo preserves paid fault/retry state and never charges the repaired load a second time.
let loading = code([@[52'u8, 7, 0, 0, 1], @[50'u8, 0]])
let loadMemo = newGasMemo(loading, limits()).value
let loadPrice = uint64(blockGas(loadMemo, CodeAddress(0)).value)
let waiting = input(loading, loadPrice+7, empty)
let fault = execute(waiting, ExecutionStepLimit(1), loadMemo).value
assert fault.exit == StepExit.Fault and uint32(fault.faultPage) == 65536
assert uint64(machineInfo(fault.machine).value.gas) == 7 and machineInfo(
    fault.machine).value.blockCharged
var image = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))
image.bytes[0] = 11
let repaired = withMemory(fault.machine, captureMemory([image], PageLimit(1)).value).value
let retry = execute(repaired, ExecutionStepLimit(2), loadMemo).value
assert retry.exit == StepExit.Halt and uint64(machineInfo(retry.machine).value.gas) == 7
assert uint64(machineInfo(retry.machine).value.registers[7]) == 11
assert uint64(machineInfo(waiting).value.gas) == loadPrice+7

proc ownershipCycle() =
  ## Parent/alias/child lifetimes, allocation refusals and failed lazy queries release all pricing/program storage without cycles.
  var owner = code([@[0'u8], @[0'u8]])
  var created = newGasMemo(owner, limits())
  assert created.error == GasMemoError.None
  var first = created.value
  created = default(GasMemoResult[GasMemo])
  owner = default(Program)
  var alias = first
  first = default(GasMemo)
  assert uint64(blockGas(alias, CodeAddress(0)).value) > 0
  let before = gasMemoInfo(alias).value
  var shared = alias
  assert uint64(blockGas(shared, CodeAddress(1)).value) > 0
  assert before.pricedBlocks == 1 and gasMemoInfo(alias).value.pricedBlocks == 2
  assert gasMemoInfo(shared).value.pricedBlocks == 2
  shared = default(GasMemo)
  let child = programOf(alias).value
  alias = default(GasMemo)
  assert instruction(child, CodeAddress(0)).error == ProgramError.None
  var bounded = limits()
  bounded.bytes = GasMemoByteLimit(codeLength(child).value*8-1)
  assert newGasMemo(child, bounded).error == GasMemoError.LimitExceeded
  bounded = limits()
  bounded.cycles = GasCycleLimit(0)
  let refused = newGasMemo(child, bounded)
  assert refused.error == GasMemoError.None
  assert blockGas(refused.value, CodeAddress(0)).error == GasMemoError.CycleLimitExceeded
  assert gasMemoInfo(refused.value).value.pricedBlocks == 0
# A prepaid entry must not populate the caller's observable lazy price memo.
let prepaidProgram = code([@[0'u8]])
let prepaidMemo = newGasMemo(prepaidProgram, limits()).value
let prepaidInput = captureMachine(prepaidProgram, empty, MachineInfo(pc: CodeAddress(0),
  gas: MachineGas(0), blockCharged: true)).value
let prepaidAnswer = execute(prepaidInput, ExecutionStepLimit(1), prepaidMemo)
assert prepaidAnswer.error == StepError.None and prepaidAnswer.value.exit == StepExit.Panic
assert gasMemoInfo(prepaidMemo).value.pricedBlocks == 0, "prepaid execution must not populate lazy prices"

ownershipCycle()
let before = getOccupiedMem()
for cycle in 0..<1000: ownershipCycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_gas_memo", 1000, before, after)
echo "PVM gas memos passed"
echo "ARC_RELEASE cycles=1000 unchanged"
