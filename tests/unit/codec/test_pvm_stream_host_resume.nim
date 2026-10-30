# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Paid host continuations reuse admitted bodies without suffix growth, repricing or target-prelink side effects.
import std/[assertions, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/[gas, plan as gas_plan, memo as gas_memo]
import ../../../src/pvm/step
import ../../../src/pvm/internal/handler_stream

proc require(ok: bool, stage: string) =
  ## Preserve an exact failure stage before this compiler's otherwise unlocated assertion.
  if not ok: echo "HOST_REUSE_ASSERT,", stage
  assert ok

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Only framing naturals use the independent codec; source opcode and operand bytes remain literal.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): Program =
  ## Explicit original instruction boundaries keep operands out of the marker map.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(code.len)
    for value in part: code.add(value)
  var bytes: seq[byte] = @[]
  appendNatural(bytes, uint64(jumps.len))
  bytes.add(if jumps.len == 0: 0'u8 else: 4'u8)
  appendNatural(bytes, uint64(code.len))
  for target in jumps:
    # Literal little-endian jump ordinals are validated independently by decodeProgram.
    for shift in 0..<4: bytes.add(byte((uint64(target) shr (8*shift)) and 255))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(uint64(bytes.len)),
    JumpCountLimit(uint64(jumps.len)))
  require(decoded.error == ProgramError.None, "decode-framed-program")
  decoded.value

proc hostSource(count: int): Program =
  ## One-byte host0 instructions do not terminate their block; a literal trap ends it.
  var parts: seq[seq[byte]] = @[]
  for index in 0..<count: parts.add(@[10'u8])
  parts.add(@[0'u8])
  owner(parts)

proc frameFor(source: Program, info: MachineInfo, nodes, work: uint64,
    cycles: GasCycleLimit = GasCycleLimit(1000000), defaults: bool = false): FlatFrame =
  ## Capture exact component ceilings, with no mapped pages or independent policy relaxation.
  var limits = defaultFlatLimits()
  if not defaults:
    # The sizing replay below also exercises the complete unchanged production default profile.
    limits.nodes = FlatNodeLimit(nodes)
    limits.preparation = FlatPreparationLimit(work)
    limits.pages = PageLimit(0)
  var admitted = prepareFlatPlan(source, cycles, limits)
  require(admitted.error == FlatError.None, "admit-source-plan")
  newFlatFrame(takeValue(admitted), [], info)

proc resources(frame: FlatFrame, identity, nodes, work: uint64) =
  ## Occupancy is a copied logical observation, not a timing, decoder-visit or RSS claim.
  if uint64(flatNodes(frame)) != nodes or flatPreparationUnits(frame) != work:
    echo "HOST_REUSE_GROWTH,", identity, ",", flatNodes(frame), ",", flatPreparationUnits(frame),
      ",", nodes, ",", work
  require(uint64(flatNodes(frame)) == nodes and flatPreparationUnits(frame) == work,
    "resource-occupancy")
  require(preparationError(frame) == FlatError.None, "no-preparation-refusal")

proc resume(frame: var FlatFrame, marker: uint64) =
  ## The genuine host boundary supplies posterior memory/scalars, never an arbitrary PC or paid flag.
  let memory = observeFlatHostMemory(frame)
  let gas = frame.info.gas
  var registers = frame.info.registers
  registers[7] = RegisterValue(marker)
  require(resumeFlatHostMemory(frame, memory, gas, registers) == StepError.None, "resume-host")

proc hostCount(count, pricing: int, alreadyPaid: bool, defaults: bool = false) =
  ## Dynamic/complete/lazy pricing must keep the same admitted body across every paid continuation.
  let source = hostSource(count)
  let nodes = uint64(count)+2
  let work = 2'u64*uint64(count+1)
  let initial = MachineInfo(gas: MachineGas(if alreadyPaid: 7'u64 else: 1000000'u64),
    blockCharged: alreadyPaid)
  var frame = frameFor(source, initial, nodes, work,
    GasCycleLimit(if alreadyPaid: 0'u64 else: 1000000'u64), defaults)
  var memo = default(GasMemo)
  if pricing == 1:
    # Complete prices are a caller-selected immutable policy, prepared outside execution.
    let priced = newGasPlan(source, GasPlanLimits(blocks: GasPlanBlockLimit(1),
      bytes: GasPlanByteLimit(uint64(count+1)*8), cycles: GasCycleLimit(1000000)))
    require(priced.error == GasPlanError.None, "prepare-complete-prices")
    require(selectFlatPrices(frame, priced.value, memo) == StepError.None, "select-complete-prices")
  elif pricing == 2:
    # Already-paid entries must not populate even a zero-cycle lazy memo.
    let priced = newGasMemo(source, GasMemoLimits(bytes: GasMemoByteLimit(uint64(count+1)*8),
      cycles: GasCycleLimit(if alreadyPaid: 0'u64 else: 1000000'u64)))
    require(priced.error == GasMemoError.None, "prepare-lazy-prices")
    memo = priced.value
    require(selectFlatPrices(frame, default(GasPlan), memo) == StepError.None, "select-lazy-prices")
  var paidGas = 0'u64
  for call in 0..<count:
    runFlat(frame, uint64(count+1-call))
    require(frame.reason == StepError.None and frame.exit == StepExit.Host, "host-progress")
    require(uint64(frame.info.pc) == uint64(call) and uint64(frame.hostCall) == 0, "literal-host-pc-id")
    require(frame.remaining == uint64(count-call), "unused-attempt-refund")
    if call == 0: paidGas = uint64(frame.info.gas)
    require(frame.info.blockCharged and uint64(frame.info.gas) == paidGas, "paid-gas-stable")
    resources(frame, uint64(count), nodes, work)
    resume(frame, uint64(call+1))
  runFlat(frame, 1)
  if frame.reason != StepError.None:
    # The unfixed-source control must identify this exact false suffix-admission refusal, not any assertion failure.
    echo "HOST_REUSE_FINAL_REFUSAL,", count, ",", ord(frame.reason), ",", ord(preparationError(
        frame)),
      ",", flatNodes(frame), ",", flatPreparationUnits(frame)
  require(frame.reason == StepError.None and frame.exit == StepExit.Panic, "final-trap")
  require(uint64(frame.info.pc) == 0 and frame.remaining == 0, "terminal-pc-attempts")
  require(uint64(frame.info.gas) == paidGas and uint64(frame.info.registers[7]) == uint64(count),
    "posterior-gas-registers")
  resources(frame, uint64(count), nodes, work)
  if alreadyPaid: require(paidGas == 7, "prepaid-input-gas")
  if pricing == 2:
    let observed = gasMemoInfo(memo)
    require(observed.error == GasMemoError.None, "observe-lazy-prices")
    require(observed.value.pricedBlocks == (if alreadyPaid: 0'u64 else: 1'u64), "lazy-price-population")

for count in [1, 2, 8, 64, 128, 4096]:
  for pricing in 0..<3:
    for paid in [false, true]: hostCount(count, pricing, paid)
hostCount(4096, 0, false, true)
echo "PASS paid host resource reuse / dynamic-plan-memo / exact occupancy / unchanged defaults"

let folded = owner([@[10'u8], @[2'u8], @[2'u8], @[10'u8], @[0'u8]])
for paid in [false, true]:
  let initial = MachineInfo(gas: MachineGas(if paid: 7'u64 else: 1000000'u64), blockCharged: paid)
  var frame = frameFor(folded, initial, 4, 10, GasCycleLimit(if paid: 0'u64 else: 1000000'u64))
  for quota in 0'u64..4'u64:
    # Restore only invocation state; cached bodies and native observations survive the independent trials.
    resetFlatFrame(frame, initial)
    runFlat(frame, 5)
    require(frame.reason == StepError.None and frame.exit == StepExit.Host, "folded-first-host")
    let gas = frame.info.gas
    resume(frame, 1)
    runFlat(frame, quota)
    if quota < 3:
      require(frame.reason == StepError.StepLimitExceeded and uint64(frame.info.pc) == 1+quota,
        "folded-exact-source-barrier")
      require(frame.info.gas == gas and frame.remaining == 0, "folded-partial-paid-gas")
      runFlat(frame, 3-quota)
    require(frame.reason == StepError.None and frame.exit == StepExit.Host and uint64(
        frame.info.pc) == 3,
      "folded-second-host")
    require(frame.remaining == (if quota > 3: quota-3 else: 0'u64), "folded-host-refund")
    require(frame.info.gas == gas, "folded-no-recharge")
    resume(frame, 2)
    runFlat(frame, 1)
    require(frame.reason == StepError.None and frame.exit == StepExit.Panic and uint64(
        frame.info.pc) == 0,
      "folded-terminal")
    resources(frame, 5, 4, 10)
  var unpaid = initial
  unpaid.pc = CodeAddress(1)
  unpaid.blockCharged = false
  resetFlatFrame(frame, unpaid)
  runFlat(frame, 4)
  require(frame.reason == StepError.InvalidPreparedProgram and preparationError(frame) ==
      FlatError.StreamLimitExceeded,
    "unpaid-interior-still-needs-admission")
  unpaid.blockCharged = true
  resetFlatFrame(frame, unpaid)
  runFlat(frame, 4)
  require(frame.reason == StepError.InvalidPreparedProgram and uint64(frame.info.pc) == 1,
    "sticky-refusal-before-paid-body")
echo "PASS folded source budgets / zero-partial-exact / paid gas / unchanged sticky refusal"

proc nativeStats(frame: FlatFrame): array[5, uint64] =
  ## Actual cache counters distinguish executable work from checked fallback; no CPU timing is interpreted.
  when defined(pvmX86Jit): flatX86Statistics(frame)
  elif defined(pvmArm64Jit): flatArmStatistics(frame)
  else: default(array[5, uint64])

when defined(pvmX86Jit):
  const nativeExpected = not defined(pvmX86JitRefuse)
elif defined(pvmArm64Jit):
  const nativeExpected = not defined(pvmArm64JitRefuse)
else:
  const nativeExpected = false

let prefix = owner([@[10'u8], @[51'u8, 1, 7], @[51'u8, 2, 11], @[51'u8, 3, 13],
  @[51'u8, 4, 17], @[10'u8], @[0'u8]])
let initialPrefix = MachineInfo(gas: MachineGas(1000000))
var prefixFrame = frameFor(prefix, initialPrefix, 8, 14)
for repeat in 0..<3:
  resetFlatFrame(prefixFrame, initialPrefix)
  let before = nativeStats(prefixFrame)
  runFlat(prefixFrame, 7)
  require(prefixFrame.reason == StepError.None and prefixFrame.exit == StepExit.Host, "prefix-first-host")
  let prepared = nativeStats(prefixFrame)
  require(prepared[2] == before[2], "native-work-not-before-host")
  if nativeExpected: require(prepared[0] > 0 and prepared[3] > 0, "actual-native-publication")
  let gas = prefixFrame.info.gas
  resume(prefixFrame, 1)
  runFlat(prefixFrame, 6)
  require(prefixFrame.reason == StepError.None and prefixFrame.exit == StepExit.Host and
    uint64(prefixFrame.info.pc) == 13, "prefix-second-host")
  for index, value in [7'u64, 11, 13, 17]:
    require(uint64(prefixFrame.info.registers[index+1]) == value, "literal-prefix-registers")
  let executed = nativeStats(prefixFrame)
  require(executed[2] == before[2]+(if nativeExpected: 4'u64 else: 0'u64), "actual-native-execution")
  require(executed[0] == prepared[0] and executed[3] == prepared[3], "native-cache-not-grown-on-resume")
  require(prefixFrame.info.gas == gas and prefixFrame.remaining == 1, "prefix-paid-budget")
  resume(prefixFrame, 2)
  runFlat(prefixFrame, 1)
  require(prefixFrame.reason == StepError.None and prefixFrame.exit == StepExit.Panic, "prefix-final-trap")
  resources(prefixFrame, 7, 8, 14)
resetFlatFrame(prefixFrame, initialPrefix)
runFlat(prefixFrame, 7)
resume(prefixFrame, 1)
let beforePartial = nativeStats(prefixFrame)
runFlat(prefixFrame, 3)
require(prefixFrame.reason == StepError.StepLimitExceeded and uint64(prefixFrame.info.pc) == 10,
  "native-prefix-partial-source-stop")
require(uint64(prefixFrame.info.registers[4]) == 0 and nativeStats(prefixFrame)[2] == beforePartial[2],
  "partial-native-prefix-declines")
runFlat(prefixFrame, 3)
require(prefixFrame.reason == StepError.None and prefixFrame.exit == StepExit.Host and
  uint64(prefixFrame.info.registers[4]) == 17, "checked-interior-prefix-completes")
resources(prefixFrame, 7, 8, 14)
for pc in [2'u64, 0xffffffff'u64]:
  # Operand bytes and out-of-range PCs cannot authorize the paid cached-body path.
  resetFlatFrame(prefixFrame, MachineInfo(pc: CodeAddress(pc), gas: MachineGas(7),
      blockCharged: true))
  runFlat(prefixFrame, 1)
  require(prefixFrame.reason == StepError.InvalidMachine and uint64(prefixFrame.info.pc) == pc,
    "invalid-paid-source-pc")
  resources(prefixFrame, 7, 8, 14)
echo "PASS cached native prefix / partial fallback / actual counters / paid source-PC guards"

let branching = owner([@[10'u8], @[81'u8, 1, 4], @[0'u8], @[50'u8, 0]])
var branchRegisters = default(RegisterFile)
branchRegisters[0] = RegisterValue(0xffff0000'u64)
var branchFrame = frameFor(branching, MachineInfo(gas: MachineGas(1000000),
    registers: branchRegisters), 7, 8)
for condition in [0'u64, 1]:
  branchRegisters[1] = RegisterValue(condition)
  resetFlatFrame(branchFrame, MachineInfo(gas: MachineGas(1000000), registers: branchRegisters))
  runFlat(branchFrame, 3)
  require(branchFrame.reason == StepError.None and branchFrame.exit == StepExit.Host, "branch-first-host")
  let gas = branchFrame.info.gas
  resume(branchFrame, 1)
  runFlat(branchFrame, 1)
  require(branchFrame.reason == StepError.StepLimitExceeded and uint64(branchFrame.info.pc) ==
    (if condition == 0: 5'u64 else: 4'u64), "prelinked-arms-do-not-reserve-attempts")
  require(branchFrame.info.gas == gas and not branchFrame.info.blockCharged, "branch-paid-reset-order")
  resources(branchFrame, 4, 7, 8)
  runFlat(branchFrame, 1)
  require(branchFrame.reason == StepError.None and branchFrame.exit ==
    (if condition == 0: StepExit.Halt else: StepExit.Panic), "literal-selected-branch-exit")
let dynamic = owner([@[10'u8], @[50'u8, 0], @[0'u8]], [3'u32])
var dynamicRegisters = default(RegisterFile)
dynamicRegisters[0] = RegisterValue(2)
var dynamicFrame = frameFor(dynamic, MachineInfo(gas: MachineGas(1000000),
    registers: dynamicRegisters), 5, 6)
runFlat(dynamicFrame, 3)
require(dynamicFrame.reason == StepError.None and dynamicFrame.exit == StepExit.Host,
    "dynamic-first-host")
let dynamicGas = dynamicFrame.info.gas
resume(dynamicFrame, 1)
runFlat(dynamicFrame, 1)
require(dynamicFrame.reason == StepError.StepLimitExceeded and uint64(dynamicFrame.info.pc) == 3,
  "dynamic-target-does-not-reserve-attempts")
require(dynamicFrame.info.gas == dynamicGas and not dynamicFrame.info.blockCharged, "dynamic-paid-reset-order")
resources(dynamicFrame, 3, 5, 6)
runFlat(dynamicFrame, 1)
require(dynamicFrame.reason == StepError.None and dynamicFrame.exit == StepExit.Panic, "dynamic-target-trap")
echo "PASS branch and dynamic target prelink / exact attempt budgets / unchanged resolver"

type Context = object ## Callback observations are invocation-local and never retained by the prepared code owner.
  calls: uint64
  paidGas: uint64

proc reply(context: var Context, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## Literal host PCs/register markers and stable paid gas are independent of another execution engine.
  let cpu = machineInfo(suspension.machine).value
  require(suspension.exit == StepExit.Host and uint64(suspension.hostCall) == 0, "public-host-id")
  require(uint64(cpu.pc) == context.calls and uint64(cpu.registers[7]) == context.calls, "public-host-pc-registers")
  if context.calls == 0: context.paidGas = uint64(cpu.gas)
  require(cpu.blockCharged and uint64(cpu.gas) == context.paidGas, "public-paid-gas")
  inc context.calls
  var registers = cpu.registers
  registers[7] = RegisterValue(context.calls)
  HostResponse(action: HostAction.Continue, gas: cpu.gas, registers: registers,
    memory: memoryOf(suspension.machine).value)

let publicCount = 4096'u64
let publicSource = hostSource(int(publicCount))
let publicInfo = MachineInfo(gas: MachineGas(1000000))
let publicInput = captureMachine(publicSource, captureMemory([], PageLimit(0)).value,
    publicInfo).value
var publicLimits = defaultPreparedLimits()
publicLimits.resources.nodes = ExecutionNodeLimit(publicCount+2)
publicLimits.resources.preparation = ExecutionPreparationLimit(2*(publicCount+1))
let publicPrepared = newPreparedProgram(publicSource, publicLimits)
require(publicPrepared.error == PreparationError.None, "public-prepare")
let prepared = publicPrepared.value
var context = Context(calls: 0, paidGas: 0)
require(executeWithHost(publicInput, context, reply, ExecutionStepLimit(0), HostCallLimit(
    publicCount),
  prepared).error == StepError.StepLimitExceeded and context.calls == 0, "public-zero-attempts")
require(preparedInfo(prepared).value.streamNodes == 0, "zero-attempts-do-not-emit")
for repeat in 0..<2:
  context = Context(calls: 0, paidGas: 0)
  let result = executeWithHost(publicInput, context, reply, ExecutionStepLimit(publicCount+1),
    HostCallLimit(publicCount), prepared)
  require(result.error == StepError.None and result.value.exit == StepExit.Panic and
    context.calls == publicCount,
    "public-complete-host-block")
  require(uint64(machineInfo(result.value.machine).value.registers[7]) == publicCount, "public-terminal-register")
  let observed = preparedInfo(prepared)
  require(observed.error == PreparationError.None and observed.value.streamNodes ==
    publicCount+2 and
    observed.value.preparationUnits == 2*(publicCount+1), "public-constant-owner-resources")
context = Context(calls: 0, paidGas: 0)
require(executeWithHost(publicInput, context, reply, ExecutionStepLimit(publicCount), HostCallLimit(
    publicCount),
  prepared).error == StepError.StepLimitExceeded and context.calls == publicCount, "public-exact-host-attempts")
context = Context(calls: 0, paidGas: 0)
require(executeWithHost(publicInput, context, reply, ExecutionStepLimit(publicCount+1),
    HostCallLimit(publicCount-1),
  prepared).error == StepError.HostCallLimitExceeded and context.calls == publicCount-1,
      "public-callback-limit")
let retained = machineInfo(publicInput).value
require(retained.pc == publicInfo.pc and retained.gas == publicInfo.gas and uint64(
    retained.registers[7]) == 0,
  "public-immutable-input")
echo "PASS public prepared host owner / callback-attempt limits / fresh immutable inputs"
