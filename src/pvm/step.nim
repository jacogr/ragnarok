# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable stepping, bounded execution and trusted host resumption.
##
## The machine supplies the exact program and paid-block flag. Prepared owners
## bind reusable pricing and execution facts to that program. Invocation registers,
## mutable memory staging and attempt budgets stay local to the call.
##
## Guest exits are completed outcomes, including OutOfGas. Local refusal exposes
## no machine or tentative debit. A memory fault retains the already-paid block
## for repair and retry. Fault and Host alone carry their guarded page or host ID.
## Raw terminal PCs and recursive host resumption are distinct boundaries.
##
## The checked handler stream implements opcode execution. Native engines and
## host adapters cross the same prepared-owner and immutable outcome contracts.

import std/assertions
import ./[program, machine, registers]
import ./gas/[gas, plan as gas_plan, memo as gas_memo]
import ./backend
export backend
when defined(polkavmRuntime):
  import std/algorithm
  import ./internal/polkavm
import ./internal/[handler_stream, execution_types, native_pipeline]
export NativeRuntime, newNativeRuntime, NativePhase, NativeState, NativeRuntimeInfo
export start, close, runtimeInfo
when defined(pvmSharedAsyncWitness):
  export pauseNativeCompiler, waitNativeCompiler
export execution_types

type
  ExecutionStepLimit* = distinct uint64 ## Local scheduling policy bounds attempted instructions; it is not guest gas or a guest exit.
  HostCallLimit* = distinct uint64 ## Local dispatch budget, independent of attempted guest instructions and guest gas.
  StepOutcome* = object ## Normal and terminal guest outcomes are completed evaluations with an inspectable snapshot.
    machine*: Machine
    engine: PvmBackend # The actual selected engine survives host suspension and terminal responses.
    case kind: StepExit
    of Fault:
      # Only a fault carries a physical aligned page address; no default page is fabricated.
      failedPage: PageAddress
    of Host:
      # The sign-extended instruction immediate retains its complete register-width bit pattern.
      callNumber: HostCallId
      # Bind the suspension to its causing PC, including adjacent identical host calls.
      callAddress: CodeAddress
    else:
      # Normal, terminal and gas outcomes have no fault metadata.
      discard
  HostAction* {.pure.} = enum ## Host continuations and terminal requests are separate from guest fault/host suspension reasons.
    Uninitialized, Continue, Halt, Panic, OutOfGas
  ScalarHostResponse* = object ## A copied CPU reply has no guest-memory or executable-state capability.
    action*: HostAction
    gas*: MachineGas
    gasDeficit*: GasDeficit # Reserved zero, validated before any posterior state is applied.
    registers*: RegisterFile
  HostResponse* = object ## A trusted host supplies posterior gas/registers/memory; it cannot choose PC, code or charged flag.
 ## Memory remains an immutable retained owner, while registers are copied by value.
    action*: HostAction
    gas*: MachineGas
    # Reserved-zero compatibility field; all current host actions carry unsigned gas.
    gasDeficit*: GasDeficit
    registers*: RegisterFile
    memory*: Memory
  StepResult* = object ## Failed/default alternatives carry only their reason; no partial machine or charge escapes.
    case status: StepError
    of None:
      # Immutable child handles form an acyclic graph without a back-reference to this result.
      completed: StepOutcome
    else:
      # Callers cannot inspect a fabricated zero/default execution state on failure.
      discard

  ExecutionCursor = object ## Trusted response application retains immutable children and copied CPU only.
    program: Program
    memory: Memory
    info: MachineInfo

type
  HostResultKind* {.pure.} = enum ## Callback selection is independent of the caller's enum: no numeric reason implies success.
    Uninitialized, Response, Failure
  HostResult*[Reason: enum] = object ## A fallible callback returns either posterior state or its own typed local refusal, never both.
    case selection: HostResultKind
    of Response:
      # Only this alternative retains a memory owner through the host response.
      response: HostResponse
    of Failure:
      # Enum-only reasons cannot smuggle partial machine state or owned resources into a failure.
      reason: Reason
    else:
      # A default callback result is malformed, not an implicit continuation.
      discard
  ScalarHostResult*[Reason: enum] = object ## Typed scalar callbacks publish a CPU reply or a local refusal.
    case selection: HostResultKind
    of Response:
      # This alternative owns only copied scalars; it cannot replace memory, code or PC.
      response: ScalarHostResponse
    of Failure:
      # Callback effects follow the existing typed-failure contract; no partial machine escapes.
      reason: Reason
    else:
      # Defaults remain malformed rather than implicitly authorizing a continuation.
      discard
  HostExecutionError* {.pure.} = enum ## Guest completion, engine refusal and callback refusal have separate guarded alternatives.
    Uninitialized, None, ExecutionFailure, HostFailure
  HostExecutionResult*[Reason: enum] = object ## Fallible execution preserves the callback's enum while exposing no machine on either failure.
    case status: HostExecutionError
    of None:
      # Completed guest outcomes retain the same immutable snapshot as ordinary StepResult.
      completed: StepOutcome
    of ExecutionFailure:
      # Scheduling, malformed replies and machine errors retain their existing StepError reason.
      executionReason: StepError
    of HostFailure:
      # Callback reasons are copied verbatim; their ordinal values have no engine-level meaning.
      hostReason: Reason
    else:
      # Default results have no outcome or selected error detail.
      discard

func hostSuccess*[Reason: enum](response: HostResponse): HostResult[Reason] =
  ## Construct a selected response; applyHostResponse still validates its fields before publication.
  HostResult[Reason](selection: HostResultKind.Response, response: response)

func hostFailure*[Reason: enum](reason: Reason): HostResult[Reason] =
  ## Construct a local callback refusal, preserving even the zero ordinal of the supplied enum.
  HostResult[Reason](selection: HostResultKind.Failure, reason: reason)

func kind*[Reason: enum](r: HostResult[Reason]): HostResultKind =
  ## Read callback selection without allowing discriminator mutation.
  r.selection

func value*[Reason: enum](r: HostResult[Reason]): HostResponse
    {.requires: r.selection == HostResultKind.Response.} =
  ## Select a callback response only after checking its kind.
  r.response

func failure*[Reason: enum](r: HostResult[Reason]): Reason
    {.requires: r.selection == HostResultKind.Failure.} =
  ## Select the local reason only after choosing the callback failure branch.
  r.reason

func scalarHostSuccess*[Reason: enum](response: ScalarHostResponse): ScalarHostResult[Reason] =
  ## Select a copied CPU reply; the engine still validates action and unsigned gas state.
  ScalarHostResult[Reason](selection: HostResultKind.Response, response: response)

func scalarHostFailure*[Reason: enum](reason: Reason): ScalarHostResult[Reason] =
  ## Preserve the caller's exact enum reason without granting a response or snapshot.
  ScalarHostResult[Reason](selection: HostResultKind.Failure, reason: reason)

func kind*[Reason: enum](r: ScalarHostResult[Reason]): HostResultKind =
  ## Inspect a scalar callback selection without exposing mutable variant fields.
  r.selection

func value*[Reason: enum](r: ScalarHostResult[Reason]): ScalarHostResponse
    {.requires: r.selection == HostResultKind.Response.} =
  ## Extract a reply only after selecting complete callback success.
  r.response

func failure*[Reason: enum](r: ScalarHostResult[Reason]): Reason
    {.requires: r.selection == HostResultKind.Failure.} =
  ## Extract only a selected scalar callback's local refusal.
  r.reason

func error*[Reason: enum](r: HostExecutionResult[Reason]): HostExecutionError =
  ## Inspect fallible execution status without permitting result forgery.
  r.status

func value*[Reason: enum](r: HostExecutionResult[Reason]): StepOutcome
    {.requires: r.status == HostExecutionError.None.} =
  ## Extract completed guest state only after successful execution.
  r.completed

func executionError*[Reason: enum](r: HostExecutionResult[Reason]): StepError
    {.requires: r.status == HostExecutionError.ExecutionFailure.} =
  ## Extract an engine reason only from the selected execution-failure alternative.
  r.executionReason

func hostError*[Reason: enum](r: HostExecutionResult[Reason]): Reason
    {.requires: r.status == HostExecutionError.HostFailure.} =
  ## Extract the original callback enum only from a selected host failure.
  r.hostReason

func error*(r: StepResult): StepError =
  ## Inspect status without permitting success forgery or retagging.
  r.status

func value*(r: StepResult): StepOutcome {.requires: r.status == StepError.None.} =
  ## Select successful evaluation before inspecting either guest outcome and its machine snapshot.
  r.completed

func terminalExit(kind: StepExit): bool {.inline.} =
  ## Final panic/halt alone normalize PC; direct comparisons avoid a runtime enum-set shift on every transition.
  kind == StepExit.Panic or kind == StepExit.Halt

func exit*(outcome: StepOutcome): StepExit =
  ## Read the guest reason without permitting an outcome to be retagged into a fabricated fault.
  outcome.kind

func backend*(outcome: StepOutcome): PvmBackend =
  ## Completed outcomes identify actual execution; local refusals carry no receipt.
  outcome.engine

func faultPage*(outcome: StepOutcome): PageAddress {.requires: outcome.kind == StepExit.Fault.} =
  ## A page address is available only after selecting the fault alternative.
  outcome.failedPage

func hostCall*(outcome: StepOutcome): HostCallId {.requires: outcome.kind == StepExit.Host.} =
  ## Host-call metadata is meaningful only after selecting the Host alternative.
  outcome.callNumber

func validPreparedHostResponse(response: HostResponse, pages: PageLimit): bool =
  ## Every accepted action obeys the prepared memory ceiling and unsigned posterior gas contract.
  let count = memoryPageCount(response.memory)
  uint64(response.gasDeficit) == 0 and count.error == MachineError.None and
      uint32(count.value) <= uint32(pages)

func hostResponseExit(action: HostAction, selected: var StepExit): bool =
  ## Owned and scalar replies share the supported action domain; host Halt remains invalid.
  case action
  of HostAction.Continue:
    selected = StepExit.Continued # Only the engine derives the genuine successor PC.
  of HostAction.Panic:
    selected = StepExit.Panic # Host terminals retain the causing PC.
  of HostAction.OutOfGas:
    selected = StepExit.OutOfGas # Unsigned posterior credit remains caller supplied.
  of HostAction.Halt, HostAction.Uninitialized:
    return false # An absent or excluded action cannot grant continuation authority.
  true

proc applyResponseCursor(cursor: var ExecutionCursor, item: Instruction,
    response: HostResponse, exit: var StepExit): StepError =
  ## A genuine causing host instruction is supplied privately; validate all posterior fields before changing the cursor.
  if uint64(response.gasDeficit) != 0: return StepError.InvalidHostResponse
  var next = cursor.info.pc
  var selected = StepExit.Continued
  if not hostResponseExit(response.action, selected): return StepError.InvalidHostResponse
  if selected == StepExit.Continued:
    # Owned instruction bounds prove the successor addition before executable membership is checked.
    next = CodeAddress(uint64(next)+1+uint64(item.skip))
    if instructionOpcode(cursor.program, next).error != ProgramError.None:
      return StepError.InvalidHostResponse # Preserve public captureMachine's executable-successor requirement.
  if readableRange(response.memory, MemoryAddress(0), MemoryLength(0)).error != MachineError.None:
    return StepError.InvalidHostResponse # Empty range validation checks genuine memory ownership without payload allocation.
  cursor.info = MachineInfo(pc: next, gas: response.gas, gasDeficit: response.gasDeficit,
    blockCharged: cursor.info.blockCharged, registers: response.registers)
  cursor.memory = response.memory
  exit = selected
  StepError.None

proc applyHostResponse*(suspension: StepOutcome, response: HostResponse): StepResult =
  ## Apply a trusted reply to a recursive execute suspension at its causing ecalli.
  ## Continue uses the decoded successor. Panic and OutOfGas keep the causing PC.
  ## A successful reply keeps the program and paid-block flag and publishes a fresh
  ## immutable machine with the supplied unsigned gas, registers and memory.
  ## No host callback, guest step or gas charge occurs here. The checks bind the
  ## reply structurally to the suspension. The caller owns host trust and replay policy.

  # Only recursive Host suspensions are valid inputs, never fault repair or terminal normalization.
  if suspension.exit != StepExit.Host:
    return StepResult(status: StepError.InvalidHostSuspension)
  let original = machineInfo(suspension.machine)
  let program = programOf(suspension.machine)
  if original.error != MachineError.None or program.error != MachineError.None:
    # Public outcome handles may be replaced by callers; never dereference invalid machine roots.
    return StepResult(status: StepError.InvalidMachine)
  if uint64(original.value.pc) != uint64(suspension.callAddress):
    # Single-step Host carries the following PC, even when it names an identical ecalli.
    return StepResult(status: StepError.InvalidHostSuspension)
  if uint64(original.value.gasDeficit) != 0:
    # A replaced terminal snapshot cannot authorize another host response.
    return StepResult(status: StepError.InvalidMachine)
  if uint64(response.gasDeficit) != 0:
    # Host gas is unsigned for every action; reserved nonzero deficit values are invalid.
    return StepResult(status: StepError.InvalidHostResponse)
  let item = instruction(program.value, original.value.pc)
  if item.error != ProgramError.None:
    # A terminal/import PC outside executable code cannot authorize a host response.
    return StepResult(status: StepError.InvalidHostSuspension)
  if item.value.opcode != 10 or uint64(item.value.x) != uint64(suspension.hostCall):
    # Keep the causing instruction and its full-width host identifier consistent.
    return StepResult(status: StepError.InvalidHostSuspension)
  let memory = memoryOf(suspension.machine)
  if memory.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  var cursor = ExecutionCursor(program: program.value, memory: memory.value, info: original.value)
  var exit = StepExit.Continued
  let applied = applyResponseCursor(cursor, item.value, response, exit)
  if applied != StepError.None: return StepResult(status: applied)
  let captured = (if exit == StepExit.Continued:
    captureMachine(cursor.program, cursor.memory, cursor.info)
    else: captureTerminalMachine(cursor.program, cursor.memory, cursor.info))
  if captured.error != MachineError.None:
    return StepResult(status: StepError.InvalidHostResponse) # Failed capture never exposes a partially applied response.
  StepResult(status: StepError.None, completed: StepOutcome(engine: suspension.engine, kind: exit,
      machine: captured.value))

const executionClasses = # Immutable byte metadata: r registers, m memory, h host, c terminating control, u unlikely, - unsupported.
  "ccu-------h-----" & # Opcodes0..15.
  "----r---------mm" & # Opcodes16..31.
  "mm------c-------" & # Opcodes32..47.
  "--crmmmmmmmmmmm-" & # Opcodes48..63.
  "------mmmm------" & # Opcodes64..79.
  "ccccccccccc-----" & # Opcodes80..95.
  "----rrrrrrrrrrr-" & # Opcodes96..111.
  "--------mmmmmmmm" & # Opcodes112..127.
  "mmmrrrrrrrrrrrrr" & # Opcodes128..143.
  "rrrrrrrrrrrrrrrr" & # Opcodes144..159.
  "rr--------cccccc" & # Opcodes160..175.
  "----c---------rr" & # Opcodes176..191.
  "rrrrrrrrrrrrrrrr" & # Opcodes192..207.
  "rrrrrrrrrrrrrrrr" & # Opcodes208..223.
  "rrrrrrr---------" & # Opcodes224..239.
  "----------------"   # Opcodes240..255.

when defined(polkavmRuntime):
  type ForeignOwner = object ## Owning foreign lifetime stays inside one prepared identity.
    handle: PolkaHandle

  proc `=copy`(destination: var ForeignOwner, source: ForeignOwner) {.error.}
    ## Copying would duplicate the exclusive raw instance lifetime.

  proc `=dup`(source: ForeignOwner): ForeignOwner {.error.}
    ## Implicit duplication must never alias one destructible foreign handle.

  proc `=wasMoved`(owner: var ForeignOwner) {.nodestroy, inline.} =
    ## A moved native handle has no allocation left to release.
    owner.handle = nil

  proc `=destroy`(owner: ForeignOwner) =
    ## ARC retires the sole native instance after all synchronous leases have returned.
    if owner.handle != nil: discard polkaDestroy(owner.handle)

type
  ExecutionLimits* = FlatLimits ## Explicit logical admission ceilings, independent of guest gas and source attempts.
  ExecutionFactLimit* = FlatFactLimit ## Maximum decoded instruction facts retained by one prepared owner.
  ExecutionNodeLimit* = FlatNodeLimit ## Maximum emitted stream nodes; stable offsets are never evicted mid-call.
  ExecutionPreparationLimit* = FlatPreparationLimit ## Cumulative source spans admitted for emission and whole-block pricing.
  RetainedMemoryByteLimit* = distinct uint64 ## Local idle baseline/private-payload ceiling; zero disables memory reuse.
  PreparedLimits* = object ## Immutable source/policy admission; callers select finite deployment resources explicitly.
    resources*: ExecutionLimits
    cycles*: GasCycleLimit
    retainedMemoryBytes*: RetainedMemoryByteLimit
  PreparationError* {.pure.} = enum ## Preparation has no partially usable success owner.
    Uninitialized, None, InvalidProgram, LimitExceeded, BackendNotBuilt, BackendUnavailable,
      BackendProgramUnsupported, BackendRevisionMismatch, BackendCapabilityUnsupported,
        BackendFailure, Busy
  PreparationResult*[T] = object ## Failed/default alternatives publish only their reason.
    case status: PreparationError
    of None: completed: T
    else: discard
  PreparedData = ref PreparedStorage ## Copies share one exclusive source/cache identity.
  PreparedStorage = object ## Source-bound code and bounded idle byte storage; active CPU and callbacks remain invocation-local.
    source: Program
    plan: FlatPlan
    stream: FlatStream
    memoryScratch: nil FlatMemoryScratch
    memoryReuses: uint64 # Diagnostic only; restored memory never relies on a hit count.
    limits: PreparedLimits
    busy: bool
    selected: PvmBackend
    native: NativeSession # Shared asynchronous pipeline; no active graph is borrowed by its compiler.
    prices: GasMemo      # Source-bound lazy prices share the same exclusive invocation lease.
    when defined(polkavmRuntime):
      foreign: ForeignOwner
  PreparedProgram* = object ## Copies share one source-bound cache identity; synchronous same-owner reentry is refused.
    data: nil PreparedData
  PreparedCacheData = ref object ## One explicitly owned worker slot retains at most one successful prepared identity.
    owner: PreparedProgram
    nativeRuntime: NativeRuntime # Closed lifetime anchor, never a raw runtime registration.
    preparations, hits: uint64   # Copied cumulative worker diagnostics never affect guest admission or results.
  PreparedProgramCache* = object ## Reference identity permits synchronous worker sharing; concurrent use remains forbidden.
    data: nil PreparedCacheData
  PreparedCacheInfo* = object ## Bounded occupancy plus actual cache activity, distinct from timing or allocator counts.
    preparations*, hits*: uint64
    prepared*: PreparedInfo
  PreparedInfo* = object ## Copied bounded occupancy; capacity and allocator overhead are not an RSS claim.
    codeBytes*: uint64 ## Immutable guest source extent; native executable storage is separate.
    decodedInstructions*, streamNodes*, preparationUnits*: uint64
    limits*: PreparedLimits
    backend*: PvmBackend
    nativeFragments*: uint64                ## Cumulative successful physical publications, including replacements.
    nativeCalls*, nativeOperations*: uint64 ## Cumulative activity across invocations of this owner.
    nativeBranchCalls*, nativeHeaderCalls*: uint64 ## Physical calls with a branch or native backedge.
    nativeCompilationMeasured*: bool ## False means the supplementary process-based compilation duration is unavailable.
    nativeCodeBytes*, nativeCompilationNs*: uint64 ## Native occupancy and supplementary construction time.
    jitBuilt*, jitPlatformSupported*, checkedFallbackEnabled*: bool
    memoryReuses*, retainedMemoryPayloadBytes*: uint64 # Idle payload admission and cumulative actual buffer reuse.

proc `=copy`(destination: var PreparedStorage, source: PreparedStorage) {.error.}
  ## Copying a handle retains identity; copying its composite storage would duplicate foreign/code ownership.

proc `=dup`(source: PreparedStorage): PreparedStorage {.error.}
  ## Prepared storage is allocated once and never implicitly duplicated by a container or return.

func defaultExecutionLimits*(): ExecutionLimits =
  ## Current supported finite profile; applications may select smaller budgets before preparation.
  defaultFlatLimits()

func defaultPreparedLimits*(cycles: GasCycleLimit = GasCycleLimit(1000000)): PreparedLimits =
  ## Checked convenience profile bounds preparation and retains at most64MiB of idle baseline/private payload.
  PreparedLimits(resources: defaultExecutionLimits(), cycles: cycles,
    retainedMemoryBytes: RetainedMemoryByteLimit(64'u64*1024*1024))

func error*[T](r: PreparationResult[T]): PreparationError =
  ## Inspect the selected result alternative without exposing its discriminator.
  r.status

func value*[T](r: PreparationResult[T]): T {.inline, requires: r.status == PreparationError.None.} =
  ## Only complete admitted results contain owners or copied diagnostics.
  r.completed

proc prepareIndependent(source: Program, limits: PreparedLimits,
    selected: PvmBackend, nativeRuntime: NativeRuntime = default(NativeRuntime)): PreparationResult[
        PreparedProgram] =
  ## Admit immutable source facts once; each invocation borrows the retained lazy stream exclusively.
  if codeLength(source).error != ProgramError.None:
    return PreparationResult[PreparedProgram](status: PreparationError.InvalidProgram)
  var admitted = prepareFlatPlan(source, limits.cycles, limits.resources, allowNative = false)
  # Requested JIT begins with the exact checked layout; all old eager ISA governance is bypassed.
  if admitted.error != FlatError.None:
    return PreparationResult[PreparedProgram](status: (if admitted.error ==
        FlatError.InvalidProgram:
      PreparationError.InvalidProgram else: PreparationError.LimitExceeded))
  let plan = takeValue(admitted)
  var stream = default(FlatStream)
  PreparationResult[PreparedProgram](status: PreparationError.None, completed: PreparedProgram(
    data: PreparedData(source: source, plan: plan, stream: move(stream), limits: limits,
        busy: false, selected: selected, memoryScratch: nil, memoryReuses: 0,
        native: (if selected == PvmBackend.Jit: newNativeSession(nativeRuntime) else: default(
            NativeSession)))))

proc newPreparedProgram*(source: Program, limits: PreparedLimits): PreparationResult[
    PreparedProgram] =
  ## Default checked-capable JIT has no hidden compiler service; explicit runtime-bound overload enables async code.
  prepareIndependent(source, limits, DefaultPvmBackend)

func programOf*(prepared: PreparedProgram): PreparationResult[Program] =
  ## Exact original source identity survives cache growth and every invocation-local refusal.
  let data = prepared.data
  if data == nil: return PreparationResult[Program](status: PreparationError.InvalidProgram)
  PreparationResult[Program](status: PreparationError.None, completed: data.source)

proc preparedInfo*(prepared: PreparedProgram): PreparationResult[PreparedInfo] =
  ## Return copied code/idle-payload occupancy and activity; no mutable byte view or callback escapes.
  let data = prepared.data
  if data == nil: return PreparationResult[PreparedInfo](status: PreparationError.InvalidProgram)
  if data.busy: return PreparationResult[PreparedInfo](status: PreparationError.Busy)
  var native = default(array[7, uint64])
  var built, supported = false
  when defined(pvmArm64Jit) or defined(pvmX86Jit):
    let observed = nativeStatistics(data.native)
    for index in 0..<5: native[index] = observed[index]
    let control = nativeControlStatistics(data.native)
    native[5] = control.branchCalls
    native[6] = control.headerCalls
    built = true
    when defined(pvmX86Jit):
      when defined(amd64) and defined(linux): supported = true
    elif defined(arm64) and (defined(linux) or defined(macosx)): supported = true
  PreparationResult[PreparedInfo](status: PreparationError.None, completed: PreparedInfo(
    codeBytes: codeLength(data.source).value, decodedInstructions: planFacts(data.plan),
    streamNodes: streamNodes(data.stream), preparationUnits: streamPreparation(data.stream),
        limits: data.limits, backend: data.selected, nativeFragments: native[0],
            nativeCalls: native[1],
        nativeOperations: native[2], nativeCodeBytes: native[3], nativeCompilationNs: native[4],
        nativeBranchCalls: native[5], nativeHeaderCalls: native[6],
        jitBuilt: built, jitPlatformSupported: supported,
        checkedFallbackEnabled: data.selected == PvmBackend.Jit,
    memoryReuses: data.memoryReuses, retainedMemoryPayloadBytes: flatMemoryScratchPayload(
        data.memoryScratch)))

when defined(pvmArm64JitOwnerReceipt):
  proc preparedArmStatistics*(prepared: PreparedProgram): PreparationResult[array[7, uint64]] =
    ## Local experiment-only copied code-cache diagnostics; exact owner availability precedes payload access.
    let data = prepared.data
    if data == nil: return PreparationResult[array[7, uint64]](
        status: PreparationError.InvalidProgram)
    PreparationResult[array[7, uint64]](status: PreparationError.None,
      completed: streamArmStatistics(data.stream))

when defined(pvmArmMacroReceipt):
  proc preparedArmMacroStatistics*(prepared: PreparedProgram): PreparationResult[array[7, uint64]] =
    ## Private copied macro counters for one retained public prepared owner.
    let data = prepared.data
    if data == nil: return PreparationResult[array[7, uint64]](
        status: PreparationError.InvalidProgram)
    PreparationResult[array[7, uint64]](status: PreparationError.None,
      completed: streamArmMacroStatistics(data.stream))

  proc preparedArmMacroResidentActive*(prepared: PreparedProgram): PreparationResult[bool] =
    ## Private copied kind evidence follows the same retained owner as macro statistics.
    let data = prepared.data
    if data == nil: return PreparationResult[bool](status: PreparationError.InvalidProgram)
    PreparationResult[bool](status: PreparationError.None,
      completed: streamArmMacroResidentActive(data.stream))

proc sourceInfo(source: Machine, cpu: var MachineInfo, owner: var Program,
    memory: var Memory): StepError =
  ## Validate immutable owners and reserved-zero debt before even a zero-attempt request.
  let info = machineInfo(source)
  let code = programOf(source)
  let pages = memoryOf(source)
  if info.error != MachineError.None or code.error != MachineError.None or pages.error !=
      MachineError.None:
    return StepError.InvalidMachine
  if uint64(info.value.gasDeficit) != 0: return StepError.InvalidMachine
  cpu = info.value
  owner = code.value
  memory = pages.value
  StepError.None

proc nativeOperations(frame: FlatFrame): uint64 =
  ## One common activity source certifies actual execution on either lowerer, never requested policy alone.
  nativeStatistics(frame.nativeSession)[2]

func actualIndependentBackend(usedNative: bool): PvmBackend =
  ## Completed native work identifies JIT execution; checked-only work remains interpreted.
  if usedNative: PvmBackend.Jit else: PvmBackend.Interpreted

proc publishFrame(frame: FlatFrame, source: Program, single: bool = false,
    original: CodeAddress = CodeAddress(0), nativeBaseline: uint64 = 0): StepResult =
  ## The one engine publishes exact recursive exits or the public Psi_1 PC convention at this adapter.
  let engine = actualIndependentBackend(nativeOperations(frame) != nativeBaseline)
  var cpu = frame.info
  var kind = frame.exit
  if single:
    if frame.reason == StepError.StepLimitExceeded: kind = StepExit.Continued
    if kind in [StepExit.Panic, StepExit.Halt]:
      let decoded = instruction(source, original)
      cpu.pc = if decoded.error == ProgramError.None and decoded.value.opcode == 0:
        CodeAddress(uint64(original)+1+uint64(decoded.value.skip)) else: original
    elif kind == StepExit.Host:
      let decoded = instruction(source, original)
      if decoded.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
      cpu.pc = CodeAddress(uint64(original)+1+uint64(decoded.value.skip))
  let memory = flatMemorySnapshot(frame)
  let captured = if kind in [StepExit.Panic, StepExit.Halt]: captureTerminalMachine(source, memory, cpu)
    else: captureMachine(source, memory, cpu)
  if captured.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  case kind
  of StepExit.Fault:
    StepResult(status: StepError.None, completed: StepOutcome(engine: engine, kind: StepExit.Fault,
      machine: captured.value,
      failedPage: frame.faultPage))
  of StepExit.Host:
    StepResult(status: StepError.None, completed: StepOutcome(engine: engine, kind: StepExit.Host,
      machine: captured.value,
      callNumber: frame.hostCall, callAddress: (if single: original else: cpu.pc)))
  else:
    StepResult(status: StepError.None, completed: StepOutcome(engine: engine, kind: kind,
        machine: captured.value))

proc runForeignFrame(source: Machine, prepared: PreparedProgram,
    limit: ExecutionStepLimit): StepResult
  ## Implemented by the included optional adapter below the common host/result declarations.

func frameCreationError(error: FlatError): StepError =
  ## Preserve a selected OS-allocation refusal while retaining all historical admission mappings.
  if error == FlatError.ResidentAllocationRefused: StepError.ResidentAllocationRefused
  else: StepError.InvalidPreparedProgram

proc runAdmittedFrame(frame: var FlatFrame, data: PreparedData, source: Machine, owner: Program,
    original: CodeAddress, limit: ExecutionStepLimit, plan: GasPlan, memo: GasMemo,
    single: bool): StepResult {.alwaysInline.} =
  ## Borrow the admitted frame through execution, publication and return of its reusable buffers.
  let policy = selectFlatPrices(frame, plan, memo)
  if policy != StepError.None: return StepResult(status: policy)
  frame.nativeSession = data.native
  restoreFlatStream(frame, data.stream)
  when NativeCheckedReadEnabled:
    # Plain execution preserves initial selection and observes only an already armed later phase.
    if nativeReplacementObservation(frame.nativeSession): beginReadProbe(frame, uint64(limit))
  let nativeBaseline = nativeOperations(frame)
  runFlat(frame, uint64(limit))
  when NativeCheckedReadEnabled:
    endReadProbeSegment(frame)
  recordNativeWork(data.native, settledNativeWork(frame, uint64(limit)))
  let answer = if single and frame.reason == StepError.None and frame.exit == StepExit.OutOfGas:
    StepResult(status: StepError.None, completed: StepOutcome(engine: PvmBackend.Interpreted,
        kind: StepExit.OutOfGas, machine: source))
    elif frame.reason == StepError.None or (single and frame.reason == StepError.StepLimitExceeded):
    publishFrame(frame, owner, single, original, nativeBaseline)
    else: StepResult(status: frame.reason)
  when NativeCheckedReadEnabled:
    finishReadProbe(frame, answer.error == StepError.None)
    finishNativeReadObservation(frame, answer.error == StepError.None)
  data.stream = takeFlatStream(frame)
  data.memoryScratch = takeFlatMemoryScratch(frame, uint64(data.limits.retainedMemoryBytes))
  answer

proc runPreparedFrame(source: Machine, prepared: PreparedProgram, limit: ExecutionStepLimit,
    plan: GasPlan, memo: GasMemo, single: bool = false): StepResult =
  ## Lease code and optional idle bytes; initialize CPU and restore complete input memory before execution.
  let selectedData = prepared.data
  if selectedData != nil and selectedData.selected in [PvmBackend.PolkaInterpreted,
      PvmBackend.PolkaCompiled]:
    if single or gasPlanInfo(plan).error == GasPlanError.None or gasMemoInfo(memo).error ==
        GasMemoError.None:
      return StepResult(status: StepError.BackendProgramUnsupported)
    return runForeignFrame(source, prepared, limit)
  let data = prepared.data
  assert data != nil
  var cpu = default(MachineInfo)
  var owner = default(Program)
  var memory = default(Memory)
  let valid = sourceInfo(source, cpu, owner, memory)
  if valid != StepError.None: return StepResult(status: valid)
  if owner != data.source: return StepResult(status: StepError.InvalidPreparedProgram)
  if uint64(limit) == 0: return StepResult(status: StepError.StepLimitExceeded)
  let decoded = instruction(owner, cpu.pc)
  if decoded.error != ProgramError.None:
    if single: return StepResult(status: StepError.InvalidMachine)
    cpu.pc = CodeAddress(0)
    let terminal = captureTerminalMachine(owner, memory, cpu)
    if terminal.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
    return StepResult(status: StepError.None, completed: StepOutcome(engine: PvmBackend.Interpreted,
        kind: StepExit.Panic, machine: terminal.value))
  var reusedMemory = false
  var created = prepareReusedFlatMemoryFrame(data.plan, memory, cpu, data.memoryScratch, reusedMemory)
  if created.error != FlatError.None: return StepResult(status: frameCreationError(created.error))
  if reusedMemory: inc data.memoryReuses
  runAdmittedFrame(borrowFrame(created), data, source, owner, cpu.pc, limit, plan, memo, single)

proc executeSelected(source: Machine, limit: ExecutionStepLimit, prepared: PreparedProgram,
    plan: GasPlan = default(GasPlan), memo: GasMemo = default(GasMemo),
        single: bool = false): StepResult =
  ## Lease the prepared execution owner for one invocation.
  ## Same-owner reentry fails before touching the active cache. Independent owners
  ## may nest. Finish the native invocation and release the lease for both completed
  ## results and local refusals.
  let data = prepared.data
  if data == nil: return StepResult(status: StepError.InvalidPreparedProgram)
  if data.busy: return StepResult(status: StepError.PreparedProgramBusy)
  data.busy = true
  beginNativeInvocation(data.native, uint64(limit))
  let answer = runPreparedFrame(source, prepared, limit, plan, memo, single)
  finishNativeInvocation(data.native, (if answer.error == StepError.None:
    observedNativeWork(data.native) else: 0'u64))
  data.busy = false
  answer

proc execute*(source: Machine, limit: ExecutionStepLimit, prepared: PreparedProgram): StepResult =
  ## Reuse admitted facts and bounded byte allocations while each call owns freshly initialized execution state.
  executeSelected(source, limit, prepared)

proc executePolicy(source: Machine, limit: ExecutionStepLimit, cycles: GasCycleLimit,
    plan: GasPlan = default(GasPlan), memo: GasMemo = default(GasMemo),
        single: bool = false): StepResult =
  ## Compatibility pricing overloads all enter this one engine; no old opcode evaluator remains.
  var cpu = default(MachineInfo)
  var owner = default(Program)
  var memory = default(Memory)
  let valid = sourceInfo(source, cpu, owner, memory)
  if valid != StepError.None: return StepResult(status: valid)
  if uint64(limit) == 0: return StepResult(status: StepError.StepLimitExceeded)
  let prepared = newPreparedProgram(owner, defaultPreparedLimits(cycles))
  if prepared.error != PreparationError.None: return StepResult(
      status: StepError.InvalidPreparedProgram)
  executeSelected(source, limit, prepared.value, plan, memo, single)

proc execute*(source: Machine, stepLimit: ExecutionStepLimit, gasLimit: GasCycleLimit): StepResult =
  ## Default recursive execution uses the checked handler stream with finite resource admission.
  executePolicy(source, stepLimit, gasLimit)

proc execute*(source: Machine, stepLimit: ExecutionStepLimit, plan: GasPlan): StepResult =
  ## A complete price owner remains an optional pricing policy, never a second execution engine.
  let settings = gasPlanInfo(plan)
  let owner = programOf(source)
  if settings.error != GasPlanError.None or (owner.error == MachineError.None and
      not matchesProgram(plan, owner.value)):
    return StepResult(status: StepError.InvalidGasPlan)
  executePolicy(source, stepLimit, settings.value.cycleLimit, plan)

proc execute*(source: Machine, stepLimit: ExecutionStepLimit, memo: GasMemo): StepResult =
  ## Lazy price diagnostics survive calls while the only execution engine owns the actual invocation.
  let settings = gasMemoInfo(memo)
  let owner = programOf(source)
  if settings.error != GasMemoError.None or (owner.error == MachineError.None and
      not matchesProgram(memo, owner.value)):
    return StepResult(status: StepError.InvalidGasMemo)
  executePolicy(source, stepLimit, settings.value.cycleLimit, memo = memo)

proc runSingleStep(source: Machine, cycles: GasCycleLimit, plan: GasPlan): StepResult =
  ## A one-instruction adapter owns no whole-program preparation and shares every checked mutation worker.
  var cpu = default(MachineInfo)
  var owner = default(Program)
  var memory = default(Memory)
  let valid = sourceInfo(source, cpu, owner, memory)
  if valid != StepError.None: return StepResult(status: valid)
  var prepared = prepareSingleFlatPlan(owner, cpu.pc, cycles)
  if prepared.error != FlatError.None: return StepResult(status: StepError.InvalidPreparedProgram)
  let admitted = takeValue(prepared)
  var created = prepareFlatMemoryFrame(admitted, memory, cpu)
  if created.error != FlatError.None: return StepResult(status: frameCreationError(created.error))
  var frame = takeValue(created)
  let policy = selectFlatPrices(frame, plan, default(GasMemo))
  if policy != StepError.None: return StepResult(status: policy)
  runFlatSingle(frame)
  if frame.reason == StepError.None and frame.exit == StepExit.OutOfGas:
    return StepResult(status: StepError.None, completed: StepOutcome(engine: PvmBackend.Interpreted,
        kind: StepExit.OutOfGas, machine: source))
  if frame.reason != StepError.None and frame.reason != StepError.StepLimitExceeded:
    return StepResult(status: frame.reason)
  publishFrame(frame, owner, true, cpu.pc)

proc scopedStep(source: Machine, cycles: GasCycleLimit, scope: range[0..3],
    plan: GasPlan = default(GasPlan)): StepResult =
  ## Capability refusal precedes affordability; actual instruction mutation always uses the one stream engine.
  let owner = programOf(source)
  let cpu = machineInfo(source)
  if owner.error != MachineError.None or cpu.error != MachineError.None:
    return StepResult(status: StepError.InvalidMachine)
  if uint64(cpu.value.gasDeficit) != 0: return StepResult(status: StepError.InvalidMachine)
  let decoded = instruction(owner.value, cpu.value.pc)
  if decoded.error != ProgramError.None: return StepResult(status: StepError.InvalidMachine)
  let category = executionClasses[int(decoded.value.opcode)]
  if category == '-' or (category in {'c', 'u'} and scope < 1) or (category == 'm' and scope < 2) or
      (category == 'h' and scope < 3):
    return StepResult(status: StepError.UnsupportedInstruction)
  runSingleStep(source, cycles, plan)

proc stepRegisters*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Evaluate one permitted register instruction with the shared checked engine.
  scopedStep(source, limit, 0)

proc stepControl*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Add control instructions while preserving exact single-step PC conventions.
  scopedStep(source, limit, 1)

proc stepMemory*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Add atomic checked loads/stores; host instructions remain outside this capability.
  scopedStep(source, limit, 2)

proc stepOnce*(source: Machine, limit: GasCycleLimit): StepResult =
  ## Evaluate every instruction under Psi_1; all mutation occurs in the same recursive engine.
  scopedStep(source, limit, 3)

proc scopedPlanStep(source: Machine, plan: GasPlan, scope: range[0..3]): StepResult =
  ## Validate exact pricing ownership before forwarding a scoped single instruction.
  let settings = gasPlanInfo(plan)
  let owner = programOf(source)
  if settings.error != GasPlanError.None or owner.error != MachineError.None or not matchesProgram(
      plan, owner.value):
    return StepResult(status: StepError.InvalidGasPlan)
  scopedStep(source, settings.value.cycleLimit, scope, plan)

proc stepRegisters*(source: Machine, plan: GasPlan): StepResult =
  ## Complete prices do not broaden the register-only capability.
  scopedPlanStep(source, plan, 0)

proc stepControl*(source: Machine, plan: GasPlan): StepResult =
  ## Control scope uses the same immutable price capability and engine.
  scopedPlanStep(source, plan, 1)

proc stepMemory*(source: Machine, plan: GasPlan): StepResult =
  ## Memory scope retains checked atomic accesses under complete prices.
  scopedPlanStep(source, plan, 2)

proc stepOnce*(source: Machine, plan: GasPlan): StepResult =
  ## Full Psi_1 scope preserves the existing price-owner validation boundary.
  scopedPlanStep(source, plan, 3)

func executionResult[Reason: enum](answer: StepResult): HostExecutionResult[Reason] =
  ## Adapt selected guest success or local refusal without fabricating callback failures.
  if answer.error == StepError.None:
    HostExecutionResult[Reason](status: HostExecutionError.None, completed: answer.value)
  else:
    HostExecutionResult[Reason](status: HostExecutionError.ExecutionFailure,
        executionReason: answer.error)

type
  ScalarHostSelector* = proc(call: HostCallId): bool {.nimcall, raises: [], noSideEffect.}
    ## Pure capability routing occurs before callback execution; false retains the owned fallback.
  ScalarHostCallback*[Context] = proc(context: var Context, call: HostCallId,
      cpu: MachineInfo): ScalarHostResponse {.nimcall, raises: [].}
    ## Copied CPU values may be retained; no memory owner, frame borrow or pointer is supplied.
  FallibleScalarHostCallback*[Context; Reason: enum] = proc(context: var Context,
      call: HostCallId, cpu: MachineInfo): ScalarHostResult[Reason] {.nimcall, raises: [].}
    ## A local callback failure preserves its enum and never publishes partial engine state.
  ResponseOnly = enum ## The response-only adapter has no callback-failure alternative.
    Reply
  ResponseCallback[Context] = proc(context: var Context,
      suspension: StepOutcome): HostResponse {.nimcall, raises: [].}
    ## The caller owns context and callback for one synchronous invocation.
  FallibleCallback[Context; Reason: enum] = proc(context: var Context,
      suspension: StepOutcome): HostResult[Reason] {.nimcall, raises: [].}
    ## Enum-valued failure remains separate from response selection.
  HostCallbacks[Context; Reason: enum] = object
    ## Ordinary callbacks retain exactly their original two invocation-local owned reply slots.
    response: nil ResponseCallback[Context]
    fallible: nil FallibleCallback[Context, Reason]
  ScalarHostCallbacks[Context; Reason: enum] = object
    ## Explicit scalar callers add three pointer slots; fixed fields avoid conditional record expansion.
    response: nil ResponseCallback[Context]
    fallible: nil FallibleCallback[Context, Reason]
    scalarCalls: nil ScalarHostSelector
    scalarResponse: nil ScalarHostCallback[Context]
    scalarFallible: nil FallibleScalarHostCallback[Context, Reason]

include ./internal/backend_execution

proc publishScalarHostTerminal(frame: FlatFrame, owner: Program, response: ScalarHostResponse,
    selected: StepExit, nativeBaseline: uint64): StepResult =
  ## Final scalar replies still materialize every dirty byte and an immutable result at the causing PC.
  assert selected in [StepExit.Panic, StepExit.OutOfGas]
  var cpu = frame.info
  cpu.gas = response.gas
  cpu.gasDeficit = response.gasDeficit
  cpu.registers = response.registers
  let memory = flatMemorySnapshot(frame)
  let captured = captureTerminalMachine(owner, memory, cpu)
  if captured.error != MachineError.None: return StepResult(status: StepError.InvalidHostResponse)
  StepResult(status: StepError.None, completed: StepOutcome(
    engine: actualIndependentBackend(nativeOperations(frame) != nativeBaseline),
    kind: selected, machine: captured.value))

proc driveHostFrame[Context; Reason: enum; Fallible, ScalarCapable: static[bool]; Callbacks](
    frame: var FlatFrame, owner: Program, context: var Context, callbacks: Callbacks,
    steps: ExecutionStepLimit, calls: HostCallLimit, pages: PageLimit): HostExecutionResult[
        Reason] {.untyped.} =
  ## Keep one private engine frame across genuine callbacks; every public observation is immutable.
  ## Callbacks is the caller's concrete fixed record; ScalarCapable selects procedure code only.
  var remaining = uint64(steps)
  var available = uint64(calls)
  let nativeBaseline = nativeOperations(frame)
  while true:
    # The engine counts attempted source instructions across every host continuation.
    let segmentBudget = remaining
    when NativeCheckedReadEnabled:
      resumeReadProbeSegment(frame, segmentBudget)
    runFlat(frame, segmentBudget)
    when NativeCheckedReadEnabled:
      endReadProbeSegment(frame)
    recordNativeWork(frame.nativeSession, settledNativeWork(frame, segmentBudget))
    remaining = frame.remaining
    if frame.reason != StepError.None:
      return executionResult[Reason](StepResult(status: frame.reason))
    if frame.exit != StepExit.Host: return executionResult[Reason](publishFrame(frame, owner,
        nativeBaseline = nativeBaseline))
    if available == 0: return executionResult[Reason](StepResult(
        status: StepError.HostCallLimitExceeded))
    dec available
    when ScalarCapable:
      # Ordinary instantiations contain neither scalar routing nor scalar reply temporaries.
      let selector = callbacks.scalarCalls
      var scalar = false
      if selector != nil:
        # Routing reads only the host identifier and cannot replay an already-effectful callback.
        scalar = selector(frame.hostCall)
      if scalar:
        let call = frame.hostCall
        let cpu = observeFlatHostScalars(frame)
        var response = default(ScalarHostResponse)
        when Fallible:
          # The selected scalar signature owns no memory and preserves the caller's typed refusal.
          let selected = callbacks.scalarFallible
          assert selected != nil
          let reply = selected(context, call, cpu)
          case reply.kind
          of HostResultKind.Response: response = reply.value
          of HostResultKind.Failure:
            return HostExecutionResult[Reason](status: HostExecutionError.HostFailure,
              hostReason: reply.failure)
          else: return executionResult[Reason](StepResult(status: StepError.InvalidHostResponse))
        else:
          # Response-only callers retain their original StepResult contract through the same driver.
          let selected = callbacks.scalarResponse
          assert selected != nil
          response = selected(context, call, cpu)
        var posteriorExit = StepExit.Continued
        if uint64(response.gasDeficit) != 0 or not hostResponseExit(response.action, posteriorExit):
          return executionResult[Reason](StepResult(status: StepError.InvalidHostResponse))
        if posteriorExit == StepExit.Continued:
          # Leave the old immutable baseline and all dirty membership intact until a real publication.
          let resumed = resumeFlatHostScalars(frame, response.gas, response.registers)
          if resumed != StepError.None: return executionResult[Reason](StepResult(status: resumed))
          # Successful scalar continuation returns to the same engine loop without owned publication.
          continue
        else:
          # A scalar terminal reply still returns complete immutable bytes at this causing ecalli.
          return executionResult[Reason](publishScalarHostTerminal(frame, owner, response,
            posteriorExit, nativeBaseline))
    # Existing callbacks keep their independent retainable snapshots and arbitrary owned posterior memory.
    let memory = observeFlatHostMemory(frame)
    let captured = captureMachine(owner, memory, frame.info)
    if captured.error != MachineError.None:
      return executionResult[Reason](StepResult(status: StepError.InvalidMachine))
    let suspension = StepOutcome(engine: actualIndependentBackend(nativeOperations(frame) !=
        nativeBaseline), kind: StepExit.Host, machine: captured.value,
      callNumber: frame.hostCall, callAddress: frame.info.pc)
    var response = default(HostResponse)
    when Fallible:
      let selected = callbacks.fallible
      assert selected != nil
      let reply = selected(context, suspension)
      case reply.kind
      of HostResultKind.Response: response = reply.value
      of HostResultKind.Failure:
        return HostExecutionResult[Reason](status: HostExecutionError.HostFailure,
            hostReason: reply.failure)
      else: return executionResult[Reason](StepResult(status: StepError.InvalidHostResponse))
    else:
      let selected = callbacks.response
      assert selected != nil
      response = selected(context, suspension)
    if not validPreparedHostResponse(response, pages):
      return executionResult[Reason](StepResult(status: StepError.InvalidHostResponse))
    if response.action == HostAction.Continue:
      # The checked resident-memory path validates source binding and applies a complete delta transactionally.
      let resumed = resumeFlatHostMemory(frame, response.memory, response.gas, response.registers)
      if resumed != StepError.None: return executionResult[Reason](StepResult(status: resumed))
    else:
      # GP host terminal actions retain their causing PC; applyHostResponse validates the trusted reply.
      return executionResult[Reason](applyHostResponse(suspension, response))
  executionResult[Reason](StepResult(status: StepError.InvalidMachine))

proc runPreparedHost[Context; Reason: enum; Fallible, ScalarCapable: static[bool]; Callbacks](
    source: Machine, prepared: PreparedProgram, context: var Context, callbacks: Callbacks,
    steps: ExecutionStepLimit, calls: HostCallLimit, plan: GasPlan,
        memo: GasMemo): HostExecutionResult[Reason] {.untyped.} =
  ## Validate and restore private input memory before moving the exclusively leased executable cache.
  let selectedData = prepared.data
  if selectedData != nil and selectedData.selected in [PvmBackend.PolkaInterpreted,
      PvmBackend.PolkaCompiled]:
    when Fallible:
      let selected = callbacks.fallible
      assert selected != nil
      return runForeignHost(source, prepared, context, selected, steps, calls)
    else:
      let selected = callbacks.response
      assert selected != nil
      return executionResult[Reason](runForeignHost(source, prepared, context, selected, steps, calls))
  let data = prepared.data
  assert data != nil
  var cpu = default(MachineInfo)
  var owner = default(Program)
  var memory = default(Memory)
  let valid = sourceInfo(source, cpu, owner, memory)
  if valid != StepError.None: return executionResult[Reason](StepResult(status: valid))
  if owner != data.source: return executionResult[Reason](StepResult(
      status: StepError.InvalidPreparedProgram))
  if uint64(steps) == 0: return executionResult[Reason](StepResult(
      status: StepError.StepLimitExceeded))
  if instruction(owner, cpu.pc).error != ProgramError.None:
    # Invalid imported terminal PCs retain recursive deblob panic semantics without calling the host.
    return executionResult[Reason](runPreparedFrame(source, prepared, steps, plan, memo))
  var reusedMemory = false
  var created = prepareReusedFlatMemoryFrame(data.plan, memory, cpu, data.memoryScratch, reusedMemory)
  if created.error != FlatError.None:
    return executionResult[Reason](StepResult(status: frameCreationError(created.error)))
  var frame = takeValue(created)
  if reusedMemory: inc data.memoryReuses
  let policy = selectFlatPrices(frame, plan, memo)
  if policy != StepError.None: return executionResult[Reason](StepResult(status: policy))
  frame.nativeSession = data.native
  restoreFlatStream(frame, data.stream)
  when NativeCheckedReadEnabled:
    beginReadProbe(frame, uint64(steps))
  let answer = driveHostFrame[Context, Reason, Fallible, ScalarCapable, Callbacks](frame, owner,
      context, callbacks, steps, calls, data.limits.resources.pages)
  when NativeCheckedReadEnabled:
    finishReadProbe(frame, answer.error == HostExecutionError.None)
    finishNativeReadObservation(frame, answer.error == HostExecutionError.None)
  data.stream = takeFlatStream(frame)
  data.memoryScratch = takeFlatMemoryScratch(frame, uint64(data.limits.retainedMemoryBytes))
  answer

proc hostSelected[Context; Reason: enum; Fallible, ScalarCapable: static[bool]; Callbacks](source: Machine,
    prepared: PreparedProgram, context: var Context,
    callbacks: Callbacks, steps: ExecutionStepLimit,
    calls: HostCallLimit, plan: GasPlan = default(GasPlan), memo: GasMemo = default(
        GasMemo)): HostExecutionResult[Reason] =
  ## A shared owner remains busy throughout callbacks; every return path retires invocation state and releases it.
  let data = prepared.data
  if data == nil: return executionResult[Reason](StepResult(
      status: StepError.InvalidPreparedProgram))
  if data.busy: return executionResult[Reason](StepResult(status: StepError.PreparedProgramBusy))
  data.busy = true
  beginNativeInvocation(data.native, uint64(steps))
  let answer = runPreparedHost[Context, Reason, Fallible, ScalarCapable, Callbacks](source,
      prepared, context, callbacks, steps, calls, plan, memo)
  finishNativeInvocation(data.native, (if answer.error == HostExecutionError.None:
    observedNativeWork(data.native) else: 0'u64))
  data.busy = false
  answer

proc hostPolicy[Context; Reason: enum; Fallible, ScalarCapable: static[bool]; Callbacks](source: Machine,
    context: var Context, callbacks: Callbacks,
    steps: ExecutionStepLimit, calls: HostCallLimit,
    cycles: GasCycleLimit, plan: GasPlan = default(GasPlan), memo: GasMemo = default(
        GasMemo)): HostExecutionResult[Reason] =
  ## Ordinary application callers enter the same engine with the explicit default finite resource profile.
  var cpu = default(MachineInfo)
  var owner = default(Program)
  var memory = default(Memory)
  let valid = sourceInfo(source, cpu, owner, memory)
  if valid != StepError.None: return executionResult[Reason](StepResult(status: valid))
  if uint64(steps) == 0: return executionResult[Reason](StepResult(
      status: StepError.StepLimitExceeded))
  let prepared = newPreparedProgram(owner, defaultPreparedLimits(cycles))
  if prepared.error != PreparationError.None:
    return executionResult[Reason](StepResult(status: StepError.InvalidPreparedProgram))
  hostSelected[Context, Reason, Fallible, ScalarCapable, Callbacks](source, prepared.value, context,
      callbacks, steps, calls, plan, memo)

func responseResult(answer: HostExecutionResult[ResponseOnly]): StepResult =
  ## Response-only callers retain the existing guarded StepResult interface.
  if answer.error == HostExecutionError.None: StepResult(status: StepError.None,
      completed: answer.value)
  elif answer.error == HostExecutionError.ExecutionFailure: StepResult(
      status: answer.executionError)
  else: StepResult(status: StepError.InvalidHostResponse)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        gasLimit: GasCycleLimit): HostExecutionResult[Reason] =
  ## Fallible host dispatch retains typed callback failures and the shared source-attempt budget.
  hostPolicy[Context, Reason, true, false, HostCallbacks[Context, Reason]](source, context,
      HostCallbacks[Context, Reason](fallible: handler), stepLimit, hostLimit, gasLimit)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit): StepResult =
  ## Ordinary callbacks use the same resident checked memory and only the new engine.
  responseResult(hostPolicy[Context, ResponseOnly, false, false, HostCallbacks[Context,
      ResponseOnly]](source, context, HostCallbacks[Context, ResponseOnly](response: handler),
          stepLimit, hostLimit, gasLimit))

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        prepared: PreparedProgram): HostExecutionResult[Reason] =
  ## Prepared callbacks share scalar executable facts while same-owner reentry remains refused.
  hostSelected[Context, Reason, true, false, HostCallbacks[Context, Reason]](source, prepared,
      context, HostCallbacks[Context, Reason](fallible: handler), stepLimit, hostLimit)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        prepared: PreparedProgram): StepResult =
  ## Active CPU and callbacks stay local; idle source/byte storage is bounded by the prepared policy.
  responseResult(hostSelected[Context, ResponseOnly, false, false, HostCallbacks[Context,
      ResponseOnly]](source, prepared, context,

HostCallbacks[Context, ResponseOnly](response: handler), stepLimit, hostLimit))

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason]
      {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, prepared: PreparedProgram,
    scalarCalls: ScalarHostSelector,
    scalarHandler: FallibleScalarHostCallback[Context, Reason]): HostExecutionResult[Reason] =
  ## Explicitly select copied CPU callbacks; all other calls and foreign policies retain the owned handler.
  hostSelected[Context, Reason, true, true, ScalarHostCallbacks[Context, Reason]](source, prepared, context,
    ScalarHostCallbacks[Context, Reason](fallible: handler, scalarCalls: scalarCalls,
      scalarFallible: scalarHandler), stepLimit, hostLimit)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse
      {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, prepared: PreparedProgram,
    scalarCalls: ScalarHostSelector, scalarHandler: ScalarHostCallback[Context]): StepResult =
  ## Response-only scalar callbacks use the same host driver and never receive a memory capability.
  responseResult(hostSelected[Context, ResponseOnly, false, true, ScalarHostCallbacks[Context,
      ResponseOnly]](source, prepared, context,
    ScalarHostCallbacks[Context, ResponseOnly](response: handler, scalarCalls: scalarCalls,
      scalarResponse: scalarHandler), stepLimit, hostLimit))

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, plan: GasPlan): HostExecutionResult[Reason] =
  ## Complete prices remain an exact-owner policy over the one execution engine.
  let settings = gasPlanInfo(plan)
  let owner = programOf(source)
  if settings.error != GasPlanError.None or owner.error != MachineError.None or not matchesProgram(
      plan, owner.value):
    return executionResult[Reason](StepResult(status: StepError.InvalidGasPlan))
  hostPolicy[Context, Reason, true, false, HostCallbacks[Context, Reason]](source, context,
      HostCallbacks[Context, Reason](fallible: handler), stepLimit, hostLimit,
      settings.value.cycleLimit, plan)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, plan: GasPlan): StepResult =
  ## Pricing compatibility never selects a legacy evaluator.
  let settings = gasPlanInfo(plan)
  let owner = programOf(source)
  if settings.error != GasPlanError.None or owner.error != MachineError.None or not matchesProgram(
      plan, owner.value):
    return StepResult(status: StepError.InvalidGasPlan)
  responseResult(hostPolicy[Context, ResponseOnly, false, false, HostCallbacks[Context,
      ResponseOnly]](source, context, HostCallbacks[Context, ResponseOnly](response: handler),
          stepLimit, hostLimit,
      settings.value.cycleLimit, plan))

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, memo: GasMemo): HostExecutionResult[Reason] =
  ## Lazy price memoization remains separate from the source-bound executable stream.
  let settings = gasMemoInfo(memo)
  let owner = programOf(source)
  if settings.error != GasMemoError.None or owner.error != MachineError.None or not matchesProgram(
      memo, owner.value):
    return executionResult[Reason](StepResult(status: StepError.InvalidGasMemo))
  hostPolicy[Context, Reason, true, false, HostCallbacks[Context, Reason]](source, context,
      HostCallbacks[Context, Reason](fallible: handler), stepLimit, hostLimit,
      settings.value.cycleLimit, memo = memo)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, memo: GasMemo): StepResult =
  ## Response-only lazy pricing preserves callback rejection and exact local source budgets.
  let settings = gasMemoInfo(memo)
  let owner = programOf(source)
  if settings.error != GasMemoError.None or owner.error != MachineError.None or not matchesProgram(
      memo, owner.value):
    return StepResult(status: StepError.InvalidGasMemo)
  responseResult(hostPolicy[Context, ResponseOnly, false, false, HostCallbacks[Context,
      ResponseOnly]](source, context, HostCallbacks[Context, ResponseOnly](response: handler),
          stepLimit, hostLimit,
      settings.value.cycleLimit, memo = memo))

proc execute*(source: Machine, steps: ExecutionStepLimit, cycles: GasCycleLimit,
    selected: PvmBackend): StepResult =
  ## Convenience calls still bind one prepared identity; retained callers can reuse that owner directly.
  let code = programOf(source)
  if code.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  let prepared = newPreparedProgram(code.value, defaultPreparedLimits(cycles), selected)
  if prepared.error != PreparationError.None: return StepResult(status: preparationFailure(
      prepared.error))
  execute(source, steps, prepared.value)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend): HostExecutionResult[Reason] =
  ## Engine choice cannot change while callbacks borrow one prepared identity.
  let code = programOf(source)
  if code.error != MachineError.None: return executionResult[Reason](StepResult(
      status: StepError.InvalidMachine))
  let prepared = newPreparedProgram(code.value, defaultPreparedLimits(cycles), selected)
  if prepared.error != PreparationError.None:
    return executionResult[Reason](StepResult(status: preparationFailure(prepared.error)))
  executeWithHost(source, context, handler, steps, calls, prepared.value)

proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend): StepResult =
  ## Ordinary hosts use the same prepared API without retaining a context pointer between invocations.
  let code = programOf(source)
  if code.error != MachineError.None: return StepResult(status: StepError.InvalidMachine)
  let prepared = newPreparedProgram(code.value, defaultPreparedLimits(cycles), selected)
  if prepared.error != PreparationError.None: return StepResult(status: preparationFailure(
      prepared.error))
  executeWithHost(source, context, handler, steps, calls, prepared.value)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason]
      {.nimcall, raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend, scalarCalls: ScalarHostSelector,
    scalarHandler: FallibleScalarHostCallback[Context, Reason]): HostExecutionResult[Reason] =
  ## One-shot scalar-capable calls preserve the same complete owner admission and selected-backend policy.
  let code = programOf(source)
  if code.error != MachineError.None:
    return executionResult[Reason](StepResult(status: StepError.InvalidMachine))
  let prepared = newPreparedProgram(code.value, defaultPreparedLimits(cycles), selected)
  if prepared.error != PreparationError.None:
    return executionResult[Reason](StepResult(status: preparationFailure(prepared.error)))
  executeWithHost(source, context, handler, steps, calls, prepared.value,
    scalarCalls, scalarHandler)

proc newPreparedProgramCache*(nativeRuntime: NativeRuntime = default(
    NativeRuntime)): PreparedProgramCache =
  ## Create one empty slot; no source, native mapping or invocation state is allocated until successful admission.
  PreparedProgramCache(data: PreparedCacheData(nativeRuntime: nativeRuntime))

proc preparedCacheInfo*(cache: PreparedProgramCache): PreparationResult[PreparedCacheInfo] =
  ## Copy bounded occupancy/activity without exposing a cached handle or fabricating zero work from a busy owner.
  let slot = cache.data
  if slot == nil: return PreparationResult[PreparedCacheInfo](
      status: PreparationError.InvalidProgram)
  let observed = preparedInfo(slot.owner)
  if observed.error != PreparationError.None:
    return PreparationResult[PreparedCacheInfo](status: observed.error)
  PreparationResult[PreparedCacheInfo](status: PreparationError.None, completed: PreparedCacheInfo(
      preparations: slot.preparations, hits: slot.hits, prepared: observed.value))

func samePreparedLimits(a, b: PreparedLimits): bool =
  ## Every resource ceiling and the gas-analysis policy bind the cache key, not just its backend/source.
  uint64(a.cycles) == uint64(b.cycles) and
    uint64(a.retainedMemoryBytes) == uint64(b.retainedMemoryBytes) and
    uint64(a.resources.codeBytes) == uint64(b.resources.codeBytes) and
    uint64(a.resources.facts) == uint64(b.resources.facts) and
    uint64(a.resources.jumps) == uint64(b.resources.jumps) and
    uint32(a.resources.pages) == uint32(b.resources.pages) and
    uint64(a.resources.nodes) == uint64(b.resources.nodes) and
    uint64(a.resources.preparation) == uint64(b.resources.preparation)

proc cachedPreparedProgram*(cache: PreparedProgramCache, source: Program, limits: PreparedLimits,
    selected: PvmBackend): PreparationResult[PreparedProgram] =
  ## Reuse exact source/policy; replace one idle successful owner atomically, leaving failed admissions retryable.
  let slot = cache.data
  if slot == nil: return newPreparedProgram(source, limits, selected)
  let current = slot.owner.data
  if current != nil:
    if current.busy: return PreparationResult[PreparedProgram](status: PreparationError.Busy)
    if current.source == source and current.selected == selected and samePreparedLimits(
        current.limits, limits):
      inc slot.hits # Modular diagnostic counters are independent of every execution/resource decision.
      return PreparationResult[PreparedProgram](status: PreparationError.None,
          completed: slot.owner)
  inc slot.preparations
  let admitted = newPreparedProgram(source, limits, selected, slot.nativeRuntime)
  if admitted.error == PreparationError.None:
    slot.owner = admitted.value # Retire the prior code/idle-byte owner; independently retained machine snapshots stay valid.
  admitted

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend, cache: PreparedProgramCache): HostExecutionResult[Reason] =
  ## An explicit worker slot owns preparation only; the existing leased engine owns every callback and invocation effect.
  let code = programOf(source)
  if code.error != MachineError.None: return executionResult[Reason](StepResult(
      status: StepError.InvalidMachine))
  let prepared = cachedPreparedProgram(cache, code.value, defaultPreparedLimits(cycles), selected)
  if prepared.error == PreparationError.Busy:
    return executionResult[Reason](StepResult(status: StepError.PreparedProgramBusy))
  if prepared.error != PreparationError.None:
    return executionResult[Reason](StepResult(status: preparationFailure(prepared.error)))
  executeWithHost(source, context, handler, steps, calls, prepared.value)

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason]
      {.nimcall, raises: [].},
    steps: ExecutionStepLimit, calls: HostCallLimit, cycles: GasCycleLimit,
    selected: PvmBackend, cache: PreparedProgramCache, scalarCalls: ScalarHostSelector,
    scalarHandler: FallibleScalarHostCallback[Context, Reason]): HostExecutionResult[Reason] =
  ## Explicit capabilities follow the same full cache key and exclusive prepared-owner admission.
  let code = programOf(source)
  if code.error != MachineError.None:
    return executionResult[Reason](StepResult(status: StepError.InvalidMachine))
  let prepared = cachedPreparedProgram(cache, code.value, defaultPreparedLimits(cycles), selected)
  if prepared.error == PreparationError.Busy:
    return executionResult[Reason](StepResult(status: StepError.PreparedProgramBusy))
  if prepared.error != PreparationError.None:
    return executionResult[Reason](StepResult(status: preparationFailure(prepared.error)))
  executeWithHost(source, context, handler, steps, calls, prepared.value,
    scalarCalls, scalarHandler)

proc backendAvailability*(selected: PvmBackend): StepError =
  ## Refuse unavailable explicit optional policies before any application resource, host or guest effect opens.
  if selected in [PvmBackend.Interpreted, PvmBackend.Jit]: return StepError.None
  let raw = @[0'u8, 0, 1, 0, 1]
  let source = decodeJamProgram(raw, CodeAddress(0), ProgramByteLimit(8), JumpCountLimit(0))
  if source.error != ProgramError.None: return StepError.BackendFailure
  let prepared = newPreparedProgram(source.value, defaultPreparedLimits(), selected)
  if prepared.error != PreparationError.None: return preparationFailure(prepared.error)
  StepError.None

proc preparedNativeState*(prepared: PreparedProgram): PreparationResult[NativeState] =
  ## Copy the shared session lifecycle only while no public invocation owns its frame/cache.
  let data = prepared.data
  if data == nil: return PreparationResult[NativeState](status: PreparationError.InvalidProgram)
  if data.busy: return PreparationResult[NativeState](status: PreparationError.Busy)
  PreparationResult[NativeState](status: PreparationError.None, completed: nativeState(data.native))
