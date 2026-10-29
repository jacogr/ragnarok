# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Public eager construction, exact-source ownership, complete entry/prefix parity and frozen retained-code work.
# @@Verification={"arc": "pvm_compiled_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, gas, step]

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Frame test-owned instruction bytes with the independent public compact-natural codec.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]]): Program =
  ## Retain genuine instruction boundaries; operand bytes never authorize an interior entry.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(code.len)
    for octet in part: code.add(octet)
  var raw = @[0'u8, 0]
  appendNatural(raw, uint64(code.len))
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for octet in mask: raw.add(octet)
  let decoded = decodeJamProgram(raw, CodeAddress(0), ProgramByteLimit(4194304), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "compiled fixture decoding"
  decoded.value

proc initial(code: Program, pc: uint64 = 0, gas: uint64 = 10000, paid: bool = false): Machine =
  ## Nonzero immutable page bytes and full-width registers expose lost state, aliases and permission errors.
  var image = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)
  for index in 0..<4096: image.bytes[index] = byte(index mod 251)
  let memory = captureMemory([image], PageLimit(4)).value
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  registers[1] = RegisterValue(65536)
  registers[7] = RegisterValue(0x123456789abcdef0'u64)
  captureMachine(code, memory, MachineInfo(pc: CodeAddress(pc), gas: MachineGas(gas),
      blockCharged: paid, registers: registers)).value

proc sameMachine(actual, expected: Machine) =
  ## Compare every CPU field, exact source identity, complete mapped bytes and permissions.
  assert machineInfo(actual).value == machineInfo(expected).value, "compiled CPU/gas/paid state"
  assert programOf(actual).value == programOf(expected).value, "compiled source identity"
  let a = memoryOf(actual).value
  let b = memoryOf(expected).value
  assert memoryPageCount(a).value == memoryPageCount(b).value, "compiled page count"
  let pages = memoryImages(a).value
  for page in pages:
    let wanted = pageImage(b, page.index)
    assert wanted.error == MachineError.None, "compiled page mapping"
    assert page.access == wanted.value.access and page.bytes == wanted.value.bytes,
        "compiled immutable memory/permission state"

proc sameOutcome(actual, expected: StepOutcome) =
  ## Backend identity differs by policy; all guest-visible terminal/fault/host facts must match.
  assert actual.exit == expected.exit, "compiled guest exit"
  if actual.exit == StepExit.Fault:
    assert actual.faultPage == expected.faultPage, "compiled fault page"
  elif actual.exit == StepExit.Host:
    assert actual.hostCall == expected.hostCall, "compiled ordered host identity"
  sameMachine(actual.machine, expected.machine)

proc same(actual, expected: StepResult) =
  ## A local failure publishes no payload; a completed result exposes complete immutable guest state.
  assert actual.error == expected.error, "compiled local result actual=" & $actual.error &
      " expected=" & $expected.error
  if actual.error == StepError.None: sameOutcome(actual.value, expected.value)

proc frozen(prepared: PreparedProgram, before: PreparedInfo) =
  ## Query the same retained owner after every public lease; successful publication and failed attempts freeze.
  let copied = preparedInfo(prepared)
  assert copied.error == PreparationError.None, "compiled released diagnostic lease"
  let after = copied.value
  assert after.backend == PvmBackend.Compiled and after.compilation == before.compilation,
      "compiled frozen source-entry partition/admission passes"
  assert after.streamNodes == before.streamNodes and after.preparationUnits ==
      before.preparationUnits,
      "compiled frozen handler materialization/preparation"
  assert after.nativeFragments == before.nativeFragments and after.nativeCodeBytes ==
      before.nativeCodeBytes,
      "compiled frozen successful publication/code bytes"
  assert after.nativeCompilationNs == before.nativeCompilationNs, "compiled construction clock"

type HostContext = object ## Ordered immutable suspensions and reply policy stay invocation-owned.
  observations: seq[StepOutcome]
  prepared: PreparedProgram
  reenter, bounded, fail: bool
  terminal: HostAction

type HostFailure = enum ## Fallible host refusal never becomes a guest panic or backend preparation error.
  Refused

proc respond(context: var HostContext, stopped: StepOutcome): HostResponse {.raises: [].} =
  ## Retain the busy lease across callbacks and repair bytes/permissions/mappings through ordinary public memory APIs.
  if context.reenter:
    assert preparedInfo(context.prepared).error == PreparationError.Busy, "compiled busy diagnostic"
    assert execute(stopped.machine, ExecutionStepLimit(1), context.prepared).error ==
        StepError.PreparedProgramBusy, "compiled same-owner callback reentry"
  context.observations.add(stopped)
  let cpu = machineInfo(stopped.machine).value
  var memory = memoryOf(stopped.machine).value
  var page = pageImage(memory, PageIndex(16)).value
  page.access = PageAccess.ReadWrite
  page.bytes[0] = byte(context.observations.len)
  memory = withPage(memory, page).value
  if not context.bounded:
    if context.observations.len == 1:
      memory = withPage(memory, PageImage(index: PageIndex(17), access: PageAccess.ReadOnly)).value
    else:
      memory = withPage(memory, PageImage(index: PageIndex(17),
          access: PageAccess.Inaccessible)).value
  HostResponse(action: context.terminal, gas: cpu.gas, registers: cpu.registers, memory: memory)

proc fallibleRespond(context: var HostContext, stopped: StepOutcome): HostResult[
    HostFailure] {.raises: [].} =
  ## The fallible public callback adapter retains the same state/reentry/mapping controls and exact typed host failure.
  let response = respond(context, stopped)
  if context.fail: hostFailure(HostFailure.Refused) else: hostSuccess[HostFailure](response)

proc entryWitness(parts: openArray[seq[byte]]) =
  ## Exercise source-static target links and fused/noop member entries through retained public owners and exact prefixes.
  let code = owner(parts)
  let limits = defaultPreparedLimits(GasCycleLimit(1000))
  let prepared = newPreparedProgram(code, limits, PvmBackend.Compiled).value
  let interpreted = newPreparedProgram(code, limits, PvmBackend.Interpreted).value
  let before = preparedInfo(prepared).value
  var pc = 0'u64
  for part in parts:
    for paid in [false, true]:
      for available in [0'u64, 1, 10000]:
        for attempts in 0..parts.len+1:
          let source = initial(code, pc, available, paid)
          same(execute(source, ExecutionStepLimit(attempts), prepared),
              execute(source, ExecutionStepLimit(attempts), interpreted))
          frozen(prepared, before)
    pc+=uint64(part.len)

let parts = [@[51'u8, 7, 5], @[51'u8, 8, 3], @[200'u8, 0x87, 9], @[200'u8, 0x87, 10],
    @[10'u8, 2], @[62'u8, 7, 0, 0, 1, 0], @[124'u8, 16], @[2'u8], @[51'u8, 8, 4],
    @[200'u8, 0x87, 9], @[200'u8, 0x87, 10], @[200'u8, 0x87, 11], @[10'u8, 3],
    @[124'u8, 16], @[0'u8]]
let code = owner(parts)
let bytes = programBytes(code).value
let limits = defaultPreparedLimits(GasCycleLimit(1000))
assert DefaultPvmBackend == PvmBackend.Jit, "compiled remains explicit"
let automatic = newPreparedProgram(code, limits).value
let automaticInfo = preparedInfo(automatic).value
assert automaticInfo.backend == PvmBackend.Jit and not automaticInfo.compilation.sealed and
    automaticInfo.streamNodes == 0, "compiled leaves default preparation lazy"
assert newPreparedProgram(default(Program), limits, PvmBackend.Compiled).error ==
    PreparationError.InvalidProgram, "compiled source preflight"
var restricted = limits
restricted.resources.facts = ExecutionFactLimit(0)
assert newPreparedProgram(code, restricted, PvmBackend.Compiled).error ==
    PreparationError.LimitExceeded, "compiled fact quota translation"
let made = newPreparedProgram(code, limits, PvmBackend.Compiled)
when defined(pvmCompiledPositiveWitness):
  # A positive CI profile cannot pass by running the unavailable-facility branch.
  assert made.error == PreparationError.None, "compiled positive source facility required " & $made.error
if made.error == PreparationError.BackendNotBuilt:
  # Ordinary JIT defines do not build the separate source-preparation facility on the landed stub.
  assert backendAvailability(PvmBackend.Compiled) == StepError.BackendNotBuilt,
      "compiled absent source-preparation facility"
elif not defined(pvmArm64Jit) and not defined(pvmX86Jit):
  assert made.error == PreparationError.BackendNotBuilt, "compiled absent native build"
elif (defined(pvmX86Jit) and not (defined(amd64) and defined(linux))) or
    (not defined(pvmX86Jit) and not (defined(arm64) and (defined(linux) or defined(macosx)))):
  assert made.error == PreparationError.BackendUnavailable, "compiled unsupported native platform"
elif defined(pvmArm64JitRefuse) or defined(pvmX86JitRefuse):
  assert made.error == PreparationError.BackendUnavailable, "compiled executable owner refusal"
  assert newPreparedProgram(owner([@[0'u8]]), limits, PvmBackend.Compiled).error ==
      PreparationError.BackendUnavailable, "compiled all-fallback executable owner refusal"
else:
  assert made.error == PreparationError.None, "compiled source-only construction " & $made.error
  let prepared = made.value
  let alias = prepared
  let baseline = preparedInfo(prepared).value
  let compilation = baseline.compilation
  assert compilation.sealed and compilation.sourceEntries == uint64(parts.len), "compiled complete entry domain"
  assert compilation.sourceEntries == compilation.nativeEntries+compilation.checkedEntries +
      compilation.capacityDeferred, "compiled source-entry partition"
  assert compilation.nativeEntries > 0 and baseline.nativeFragments > 0 and
      baseline.nativeCodeBytes > 0,
      "compiled positive native construction"
  assert baseline.nativeCalls == 0 and baseline.nativeOperations == 0,
      "compiled constructor executes no guest/native work"
  assert baseline.checkedFallbackEnabled, "compiled explicit checked fallback policy"
  when defined(pvmSourceSealingReceipt):
    assert compilation.compilationPasses > 0, "compiled attempted-admission instrumentation active"
  let interpreted = newPreparedProgram(code, limits, PvmBackend.Interpreted).value
  assert not preparedInfo(interpreted).value.compilation.sealed and
      preparedInfo(interpreted).value.nativeFragments == 0, "compiled preserves forced interpretation"
  let input = initial(code)
  same(execute(input, ExecutionStepLimit(5), GasCycleLimit(1000), PvmBackend.Compiled),
      execute(input, ExecutionStepLimit(5), interpreted))
  var convenience = HostContext(terminal: HostAction.Continue)
  var convenienceExpected = HostContext(terminal: HostAction.Continue)
  same(executeWithHost(input, convenience, respond, ExecutionStepLimit(30), HostCallLimit(3),
      GasCycleLimit(1000), PvmBackend.Compiled), executeWithHost(input, convenienceExpected,
      respond, ExecutionStepLimit(30), HostCallLimit(3), interpreted))
  for invocation in 0..<3:
    # Each invocation starts from unchanged input, while aliases lease the same constructed code and live counters.
    var actualContext = HostContext(prepared: alias, reenter: true, terminal: HostAction.Continue)
    var expectedContext = HostContext(terminal: HostAction.Continue)
    assert actualContext.observations.len == 0, "compiled no preparation host effects"
    let actual = executeWithHost(input, actualContext, respond, ExecutionStepLimit(30),
        HostCallLimit(3), alias)
    let expected = executeWithHost(input, expectedContext, respond, ExecutionStepLimit(30),
        HostCallLimit(3), interpreted)
    same(actual, expected)
    assert actual.error == StepError.None and actual.value.backend == PvmBackend.Compiled,
        "compiled actual native public receipt"
    assert actualContext.observations.len == 2 and expectedContext.observations.len == 2,
        "compiled complete ordered host sequence"
    for index in 0..<actualContext.observations.len:
      sameOutcome(actualContext.observations[index], expectedContext.observations[index])
    frozen(prepared, baseline)
    assert programBytes(code).value == bytes, "compiled original program bytes"
    sameMachine(input, initial(code))
  let live = preparedInfo(prepared).value
  assert live.nativeCalls > baseline.nativeCalls and live.nativeOperations >
      baseline.nativeOperations,
      "compiled execution counters remain live"
  var pc = 0'u64
  for part in parts:
    for paid in [false, true]:
      for available in [0'u64, 1, 10000]:
        for budget in 0..parts.len+1:
          # Both members of retained folds/noops and every early budget/fault/host prefix stay independently checked.
          let start = initial(code, pc, available, paid)
          same(execute(start, ExecutionStepLimit(budget), alias),
              execute(start, ExecutionStepLimit(budget), interpreted))
          frozen(prepared, baseline)
    pc+=uint64(part.len)
  let wrong = initial(owner(parts))
  assert execute(wrong, ExecutionStepLimit(30), alias).error == StepError.InvalidPreparedProgram,
      "compiled equal bytes do not confer source identity"
  frozen(prepared, baseline)
  for action in [HostAction.Panic, HostAction.OutOfGas]:
    # Terminal host actions keep the causing PC and the bound actual-engine identity before stream restoration.
    var actualContext = HostContext(terminal: action)
    var expectedContext = HostContext(terminal: action)
    let actual = executeWithHost(input, actualContext, respond, ExecutionStepLimit(30),
        HostCallLimit(3), alias)
    let expected = executeWithHost(input, expectedContext, respond, ExecutionStepLimit(30),
        HostCallLimit(3), interpreted)
    same(actual, expected)
    assert actual.value.backend == PvmBackend.Compiled, "compiled terminal host receipt"
    frozen(prepared, baseline)
  for action in [HostAction.Halt, HostAction.Uninitialized]:
    # Invalid host actions remain typed refusals and cannot poison a later lease of the same code owner.
    var context = HostContext(terminal: action)
    let invalid = executeWithHost(input, context, respond, ExecutionStepLimit(30), HostCallLimit(3), alias)
    assert invalid.error == StepError.InvalidHostResponse, "compiled invalid terminal host action"
    frozen(prepared, baseline)
  for fail in [false, true]:
    # Both completed and rejected fallible callbacks release the same owner without altering frozen work.
    var context = HostContext(prepared: alias, reenter: true, fail: fail,
        terminal: HostAction.Continue)
    let result = executeWithHost(input, context, fallibleRespond, ExecutionStepLimit(30),
        HostCallLimit(3), alias)
    if fail:
      assert result.error == HostExecutionError.HostFailure and result.hostError ==
          HostFailure.Refused,
          "compiled typed host refusal"
    else:
      assert result.error == HostExecutionError.None, "compiled fallible host completion"
    frozen(prepared, baseline)
  for budget in [0, 1]:
    var context = HostContext(terminal: HostAction.Continue)
    let result = executeWithHost(input, context, respond, ExecutionStepLimit(30), HostCallLimit(
        budget), alias)
    assert result.error == StepError.HostCallLimitExceeded and context.observations.len == budget,
        "compiled exact host budget prefix"
    frozen(prepared, baseline)
  restricted = limits
  restricted.resources.pages = PageLimit(1)
  let bounded = newPreparedProgram(code, restricted, PvmBackend.Compiled).value
  let boundedInfo = preparedInfo(bounded).value
  var tooManyPages = HostContext(terminal: HostAction.Continue)
  let rejectedReply = executeWithHost(input, tooManyPages, respond, ExecutionStepLimit(30),
      HostCallLimit(3), bounded)
  assert rejectedReply.error == StepError.InvalidHostResponse, "compiled host page-limit refusal"
  var recovered = HostContext(bounded: true, terminal: HostAction.Continue)
  let recoveredReply = executeWithHost(input, recovered, respond, ExecutionStepLimit(30),
      HostCallLimit(3), bounded)
  assert recoveredReply.error == StepError.None, "compiled reuse after invalid host reply"
  frozen(bounded, boundedInfo)
  restricted = limits
  restricted.resources.nodes = ExecutionNodeLimit(baseline.streamNodes-1)
  assert newPreparedProgram(code, restricted, PvmBackend.Compiled).error ==
      PreparationError.LimitExceeded,
      "compiled node quota is transactional refusal"
  restricted = limits
  restricted.resources.preparation = ExecutionPreparationLimit(baseline.preparationUnits-1)
  assert newPreparedProgram(code, restricted, PvmBackend.Compiled).error ==
      PreparationError.LimitExceeded,
      "compiled preparation quota is transactional refusal"
  restricted.resources.preparation = ExecutionPreparationLimit(baseline.preparationUnits)
  restricted.resources.nodes = ExecutionNodeLimit(baseline.streamNodes)
  assert newPreparedProgram(code, restricted, PvmBackend.Compiled).error == PreparationError.None,
      "compiled exact node/preparation boundary"
  let fallbackCode = owner([@[2'u8], @[0'u8]])
  let fallback = newPreparedProgram(fallbackCode, limits, PvmBackend.Compiled).value
  let fallbackInfo = preparedInfo(fallback).value
  assert fallbackInfo.compilation.sealed and fallbackInfo.compilation.nativeEntries == 0 and
      fallbackInfo.nativeFragments == 0, "compiled honest zero-native source"
  let checked = newPreparedProgram(fallbackCode, limits, PvmBackend.Interpreted).value
  let fallbackInput = initial(fallbackCode)
  let fallbackResult = execute(fallbackInput, ExecutionStepLimit(2), fallback)
  same(fallbackResult, execute(fallbackInput, ExecutionStepLimit(2), checked))
  assert fallbackResult.value.backend == PvmBackend.Interpreted, "compiled all-fallback actual engine"
  frozen(fallback, fallbackInfo)
  let zeroCycles = defaultPreparedLimits(GasCycleLimit(0))
  let badPrice = newPreparedProgram(fallbackCode, zeroCycles, PvmBackend.Compiled)
  assert badPrice.error == PreparationError.None, "compiled entry pricing errors are delayed"
  let paidInput = initial(fallbackCode, paid = true)
  assert execute(paidInput, ExecutionStepLimit(2), badPrice.value).error == StepError.None,
      "compiled paid entry never observes an unpaid price error"
  let checkedPrice = newPreparedProgram(fallbackCode, zeroCycles, PvmBackend.Interpreted).value
  same(execute(fallbackInput, ExecutionStepLimit(2), badPrice.value),
      execute(fallbackInput, ExecutionStepLimit(2), checkedPrice))
  var many: seq[seq[byte]] = @[]
  for blockIndex in 0..<1100:
    # Unreachable native candidates consume the unchanged publication allowance during construction.
    for operation in 0..<4: many.add(@[100'u8, 16, 1])
    many.add(@[0'u8])
  let crowdedCode = owner(many)
  let crowded = newPreparedProgram(crowdedCode, limits, PvmBackend.Compiled).value
  let crowdedInfo = preparedInfo(crowded).value
  assert crowdedInfo.compilation.capacityDeferred > 0, "compiled native-capacity deferred entries reported"
  let crowdedChecked = newPreparedProgram(crowdedCode, limits, PvmBackend.Interpreted).value
  let late = initial(crowdedCode, pc = 1099'u64*13)
  same(execute(late, ExecutionStepLimit(5), crowded), execute(late, ExecutionStepLimit(5),
      crowdedChecked))
  frozen(crowded, crowdedInfo)
  let faultCode = owner([@[51'u8, 7, 5], @[51'u8, 8, 3], @[200'u8, 0x87, 9], @[200'u8, 0x87, 10],
      @[62'u8, 7, 0, 16, 1, 0], @[58'u8, 8, 0, 16, 1, 0], @[0'u8]])
  let faultOwner = newPreparedProgram(faultCode, limits, PvmBackend.Compiled).value
  let faultInfo = preparedInfo(faultOwner).value
  let faultChecked = newPreparedProgram(faultCode, limits, PvmBackend.Interpreted).value
  let faultInput = initial(faultCode)
  let actualFault = execute(faultInput, ExecutionStepLimit(10), faultOwner)
  let expectedFault = execute(faultInput, ExecutionStepLimit(10), faultChecked)
  same(actualFault, expectedFault)
  assert actualFault.value.exit == StepExit.Fault, "compiled genuine missing-page fault"
  let stopped = machineInfo(actualFault.value.machine).value
  assert stopped.blockCharged, "compiled fault retains paid state"
  let repaired = withPage(memoryOf(actualFault.value.machine).value,
      PageImage(index: PageIndex(17), access: PageAccess.ReadWrite)).value
  let resumed = withMemory(actualFault.value.machine, repaired).value
  let expectedResume = withMemory(expectedFault.value.machine, repaired).value
  let repairedResult = execute(resumed, ExecutionStepLimit(10), faultOwner)
  same(repairedResult, execute(expectedResume, ExecutionStepLimit(10), faultChecked))
  assert machineInfo(repairedResult.value.machine).value.gas == stopped.gas,
      "compiled fault retry never double-charges the paid block"
  frozen(faultOwner, faultInfo)
  entryWitness([@[51'u8, 7, 1], @[40'u8, 6], @[51'u8, 7, 99], @[0'u8], @[0'u8]])
  entryWitness([@[51'u8, 7, 5], @[51'u8, 8, 3], @[200'u8, 0x87, 9], @[200'u8, 0x87, 10],
      @[81'u8, 0x87, 3], @[0'u8]])
  entryWitness([@[151'u8, 16, 1], @[152'u8, 16, 1], @[131'u8, 16, 1], @[2'u8],
      @[200'u8, 16, 2], @[139'u8, 16, 3], @[2'u8], @[0'u8]])
  entryWitness([@[2'u8], @[2'u8], @[50'u8, 0]])

if made.error != PreparationError.None:
  # Typed capability refusal propagates through the public host convenience path before a single callback.
  var context = HostContext(terminal: HostAction.Continue)
  let refused = executeWithHost(initial(code), context, respond, ExecutionStepLimit(30),
      HostCallLimit(3), GasCycleLimit(1000), PvmBackend.Compiled)
  let expected = if made.error == PreparationError.BackendNotBuilt: StepError.BackendNotBuilt
    else: StepError.BackendUnavailable
  assert refused.error == expected and context.observations.len == 0, "compiled precise host capability refusal"
  assert execute(initial(code), ExecutionStepLimit(30), GasCycleLimit(1000),
      PvmBackend.Compiled).error == expected, "compiled precise direct capability refusal"
  assert backendAvailability(PvmBackend.Compiled) == expected, "compiled precise startup capability refusal"

proc lifecycle() =
  ## Copy/move handles share one composite owner; all invocation and executable resources retire on return/refusal.
  let created = newPreparedProgram(code, limits, PvmBackend.Compiled)
  if created.error == PreparationError.None:
    var copied = created.value
    let retained = copied
    let moved = move(copied)
    assert programOf(copied).error == PreparationError.InvalidProgram, "compiled moved-from handle disarmed"
    assert programOf(moved).value == programOf(retained).value, "compiled move preserves shared source"
    let before = preparedInfo(retained).value
    let source = initial(code)
    same(execute(source, ExecutionStepLimit(4), moved), execute(source, ExecutionStepLimit(4), retained))
    frozen(moved, before)
  else:
    assert created.error == made.error, "compiled lifecycle precise capability refusal"

lifecycle()
let occupiedBefore = getOccupiedMem()
for cycle in 0..<1000: lifecycle()
let occupiedAfter = getOccupiedMem()
assert occupiedBefore == occupiedAfter, "compiled complete/refused owner ARC cleanup"
recordArcRelease("pvm_compiled", 1000, occupiedBefore, occupiedAfter)
stdout.writeLine("PASS public eager PVM compilation")
