# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 immutable stepping/execution and trusted host adapters over prepared engine boundaries.
## Local policy refusals publish no partial machine; all successful observations own immutable snapshots.
import std/assertions
import ./[program, machine, registers, gas, gas_plan, gas_memo, backend]
export backend
when defined(polkavmRuntime):
  import std/algorithm
  import ./internal/polkavm
import ./internal/[handler_stream, execution_types]
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

proc applyResponseCursor(cursor: var ExecutionCursor, item: Instruction,
    response: HostResponse, exit: var StepExit): StepError =
  ## A genuine causing host instruction is supplied privately; validate all posterior fields before changing the cursor.
  if uint64(response.gasDeficit) != 0: return StepError.InvalidHostResponse
  var next = cursor.info.pc
  var selected = StepExit.Continued
  case response.action
  of HostAction.Continue:
    next = CodeAddress(uint64(next)+1+uint64(item.skip)) # Owned instruction bounds prove the successor addition.
    if instructionOpcode(cursor.program, next).error != ProgramError.None:
      return StepError.InvalidHostResponse # Preserve public captureMachine's executable-successor requirement.
  of HostAction.Panic:
    selected = StepExit.Panic # Host terminal replies retain the causing PC and posterior state.
  of HostAction.OutOfGas:
    selected = StepExit.OutOfGas
  of HostAction.Halt, HostAction.Uninitialized:
    return StepError.InvalidHostResponse # GP PR533 excludes Halt; an unselected response never implies continuation.
  if readableRange(response.memory, MemoryAddress(0), MemoryLength(0)).error != MachineError.None:
    return StepError.InvalidHostResponse # Empty range validation checks genuine memory ownership without payload allocation.
  cursor.info = MachineInfo(pc: next, gas: response.gas, gasDeficit: response.gasDeficit,
    blockCharged: cursor.info.blockCharged, registers: response.registers)
  cursor.memory = response.memory
  exit = selected
  StepError.None

proc applyHostResponse*(suspension: StepOutcome, response: HostResponse): StepResult =
  ## Apply Psi_H's posterior host state to a recursive execute suspension at its causing ecalli.
  ## The host has already selected its action and gas; this function invokes no host or guest work.
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
  PreparedLimits* = object ## Immutable source/policy admission; callers select finite deployment resources explicitly.
    resources*: ExecutionLimits
    cycles*: GasCycleLimit
  PreparationError* {.pure.} = enum ## Preparation has no partially usable success owner.
    Uninitialized, None, InvalidProgram, LimitExceeded, BackendNotBuilt, BackendUnavailable,
      BackendProgramUnsupported, BackendRevisionMismatch, BackendCapabilityUnsupported,
        BackendFailure, Busy
  PreparationResult*[T] = object ## Failed/default alternatives publish only their reason.
    case status: PreparationError
    of None: completed: T
    else: discard
  PreparedData = ref PreparedStorage ## Copies share one exclusive source/cache identity.
  PreparedStorage = object ## Exclusive cached executable facts never retain an invocation's CPU, memory or callbacks.
    source: Program
    plan: FlatPlan
    stream: FlatStream
    limits: PreparedLimits
    busy: bool
    selected: PvmBackend
    prices: GasMemo # Source-bound lazy prices share the same exclusive invocation lease.
    when defined(polkavmRuntime):
      foreign: ForeignOwner
  PreparedProgram* = object ## Copies share one source-bound cache identity; synchronous same-owner reentry is refused.
    data: nil PreparedData
  PreparedInfo* = object ## Copied bounded occupancy; capacity and allocator overhead are not an RSS claim.
    codeBytes*, decodedInstructions*, streamNodes*, preparationUnits*: uint64
    limits*: PreparedLimits
    backend*: PvmBackend
    nativeFragments*, nativeCalls*, nativeOperations*: uint64
    jitBuilt*, jitPlatformSupported*, checkedFallbackEnabled*: bool

proc `=copy`(destination: var PreparedStorage, source: PreparedStorage) {.error.}
  ## Copying a handle retains identity; copying its composite storage would duplicate foreign/code ownership.
proc `=dup`(source: PreparedStorage): PreparedStorage {.error.}
  ## Prepared storage is allocated once and never implicitly duplicated by a container or return.

func defaultExecutionLimits*(): ExecutionLimits =
  ## Current supported finite profile; applications may select smaller budgets before preparation.
  defaultFlatLimits()

func defaultPreparedLimits*(cycles: GasCycleLimit = GasCycleLimit(1000000)): PreparedLimits =
  ## Explicit convenience profile preserves all runtime checks and a finite independent preparation allowance.
  PreparedLimits(resources: defaultExecutionLimits(), cycles: cycles)

func error*[T](r: PreparationResult[T]): PreparationError =
  ## Inspect the selected result alternative without exposing its discriminator.
  r.status

func value*[T](r: PreparationResult[T]): T {.inline, requires: r.status == PreparationError.None.} =
  ## Only complete admitted results contain owners or copied diagnostics.
  r.completed

func compiledPreparationFailure(reason: FlatError, callerPolicy: bool): PreparationError =
  ## Translate the shared contract without turning unexpected/default/success states into usable owners.
  case reason
  of FlatError.InvalidProgram:
    # Malformed caller source is distinct from a hook rejecting an already admitted immutable plan.
    if callerPolicy: PreparationError.InvalidProgram else: PreparationError.BackendFailure
  of FlatError.CodeLimitExceeded, FlatError.FactLimitExceeded, FlatError.JumpLimitExceeded,
      FlatError.PageLimitExceeded, FlatError.StreamLimitExceeded,
          FlatError.PreparationLimitExceeded:
    PreparationError.LimitExceeded
  of FlatError.InvalidPolicy:
    # Invalid caller limits are a policy refusal; an already admitted invalid source plan is an internal failure.
    if callerPolicy: PreparationError.LimitExceeded else: PreparationError.BackendFailure
  of FlatError.NativeNotBuilt: PreparationError.BackendNotBuilt
  of FlatError.NativePlatformUnsupported, FlatError.NativeStorageUnavailable:
    PreparationError.BackendUnavailable
  of FlatError.Uninitialized, FlatError.None, FlatError.InvalidMemory: PreparationError.BackendFailure

proc prepareIndependent(source: Program, limits: PreparedLimits,
    selected: PvmBackend): PreparationResult[PreparedProgram] =
  ## Decode immutable facts once; executable nodes and prices remain lazy, exclusive and source-bound.
  if codeLength(source).error != ProgramError.None:
    return PreparationResult[PreparedProgram](status: PreparationError.InvalidProgram)
  var admitted = prepareFlatPlan(source, limits.cycles, limits.resources, allowNative = selected in
      [PvmBackend.Jit, PvmBackend.Compiled])
  if admitted.error != FlatError.None:
    # Existing lazy policies retain their mapping; the new contract distinguishes shared capability refusals.
    if selected == PvmBackend.Compiled:
      return PreparationResult[PreparedProgram](status: compiledPreparationFailure(admitted.error, true))
    return PreparationResult[PreparedProgram](status: (if admitted.error ==
        FlatError.InvalidProgram:
      PreparationError.InvalidProgram else: PreparationError.LimitExceeded))
  let plan = takeValue(admitted)
  if selected == PvmBackend.Compiled:
    # This interface increment publishes no compiled owner, even if a future hook unexpectedly returns success.
    # A separately qualified implementation must explicitly adopt and lease the returned stream before enabling it.
    let constructed = prepareFlatStream(plan)
    return PreparationResult[PreparedProgram](status: compiledPreparationFailure(constructed.error, false))
  PreparationResult[PreparedProgram](status: PreparationError.None, completed: PreparedProgram(
    data: PreparedData(source: source, plan: plan, stream: default(FlatStream), limits: limits,
        busy: false, selected: selected)))

proc newPreparedProgram*(source: Program, limits: PreparedLimits): PreparationResult[
    PreparedProgram] =
  ## The independent default uses native fragments where supported and retains the checked interpreter fallback.
  prepareIndependent(source, limits, DefaultPvmBackend)

func programOf*(prepared: PreparedProgram): PreparationResult[Program] =
  ## Exact original source identity survives cache growth and every invocation-local refusal.
  let data = prepared.data
  if data == nil: return PreparationResult[Program](status: PreparationError.InvalidProgram)
  PreparationResult[Program](status: PreparationError.None, completed: data.source)

proc preparedInfo*(prepared: PreparedProgram): PreparationResult[PreparedInfo] =
  ## Return copied logical component occupancy; no invocation state is retained or exposed.
  let data = prepared.data
  if data == nil: return PreparationResult[PreparedInfo](status: PreparationError.InvalidProgram)
  if data.busy: return PreparationResult[PreparedInfo](status: PreparationError.Busy)
  var native = default(array[7, uint64])
  var built, supported = false
  when defined(pvmArm64Jit) or defined(pvmX86Jit):
    native = streamNativeStatistics(data.stream)
    built = true
    when defined(pvmX86Jit):
      when defined(amd64) and defined(linux): supported = true
    elif defined(arm64) and (defined(linux) or defined(macosx)): supported = true
  PreparationResult[PreparedInfo](status: PreparationError.None, completed: PreparedInfo(
    codeBytes: codeLength(data.source).value, decodedInstructions: planFacts(data.plan),
    streamNodes: streamNodes(data.stream), preparationUnits: streamPreparation(data.stream),
        limits: data.limits, backend: data.selected, nativeFragments: native[0],
            nativeCalls: native[1],
        nativeOperations: native[2], jitBuilt: built, jitPlatformSupported: supported,
        checkedFallbackEnabled: data.selected == PvmBackend.Jit))

when defined(pvmArm64JitOwnerReceipt):
  proc preparedArmStatistics*(prepared: PreparedProgram): PreparationResult[array[7, uint64]] =
    ## Local experiment-only copied code-cache diagnostics; exact owner availability precedes payload access.
    let data = prepared.data
    if data == nil: return PreparationResult[array[7, uint64]](
        status: PreparationError.InvalidProgram)
    PreparationResult[array[7, uint64]](status: PreparationError.None,
      completed: streamArmStatistics(data.stream))

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
  ## Copied counters are read only at publication/preparation boundaries, never in the guest hot loop.
  when defined(pvmX86Jit): flatX86Statistics(frame)[2]
  elif defined(pvmArm64Jit): flatArmStatistics(frame)[2]
  else: 0

proc publishFrame(frame: FlatFrame, source: Program, single: bool = false,
    original: CodeAddress = CodeAddress(0), nativeBaseline: uint64 = 0): StepResult =
  ## The one engine publishes exact recursive exits or the public Psi_1 PC convention at this adapter.
  let engine = if nativeOperations(frame) != nativeBaseline: PvmBackend.Jit else: PvmBackend.Interpreted
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

proc runPreparedFrame(source: Machine, prepared: PreparedProgram, limit: ExecutionStepLimit,
    plan: GasPlan, memo: GasMemo, single: bool = false): StepResult =
  ## Borrow only the prepared stream; CPU and private memory are created and retired inside this invocation.
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
  var created = prepareFlatMemoryFrame(data.plan, memory, cpu)
  if created.error != FlatError.None: return StepResult(status: StepError.InvalidPreparedProgram)
  var frame = takeValue(created)
  let policy = selectFlatPrices(frame, plan, memo)
  if policy != StepError.None: return StepResult(status: policy)
  restoreFlatStream(frame, data.stream)
  let nativeBaseline = nativeOperations(frame)
  runFlat(frame, uint64(limit))
  let answer = if single and frame.reason == StepError.None and frame.exit == StepExit.OutOfGas:
    StepResult(status: StepError.None, completed: StepOutcome(engine: PvmBackend.Interpreted,
        kind: StepExit.OutOfGas, machine: source))
    elif frame.reason == StepError.None or (single and frame.reason == StepError.StepLimitExceeded):
    publishFrame(frame, owner, single, cpu.pc, nativeBaseline)
    else: StepResult(status: frame.reason)
  data.stream = takeFlatStream(frame)
  answer

proc executeSelected(source: Machine, limit: ExecutionStepLimit, prepared: PreparedProgram,
    plan: GasPlan = default(GasPlan), memo: GasMemo = default(GasMemo),
        single: bool = false): StepResult =
  ## Same-owner synchronous reentry is rejected; every exit releases the cache lease.
  let data = prepared.data
  if data == nil: return StepResult(status: StepError.InvalidPreparedProgram)
  if data.busy: return StepResult(status: StepError.PreparedProgramBusy)
  data.busy = true
  let answer = runPreparedFrame(source, prepared, limit, plan, memo, single)
  data.busy = false
  answer

proc execute*(source: Machine, limit: ExecutionStepLimit, prepared: PreparedProgram): StepResult =
  ## Reuse admitted facts and stream nodes while each call owns fresh CPU and memory.
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
  if created.error != FlatError.None: return StepResult(status: StepError.InvalidPreparedProgram)
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
  ResponseOnly = enum ## The response-only adapter has no callback-failure alternative.
    Reply
  ResponseCallback[Context] = proc(context: var Context,
      suspension: StepOutcome): HostResponse {.nimcall, raises: [].}
    ## The caller owns context and callback for one synchronous invocation.
  FallibleCallback[Context; Reason: enum] = proc(context: var Context,
      suspension: StepOutcome): HostResult[Reason] {.nimcall, raises: [].}
    ## Enum-valued failure remains separate from response selection.
  HostCallbacks[Context; Reason: enum] = object
    ## Exactly one typed slot is selected at compile time; neither is retained in prepared state.
    response: nil ResponseCallback[Context]
    fallible: nil FallibleCallback[Context, Reason]

include ./internal/backend_execution

proc driveHostFrame[Context; Reason: enum; Fallible: static[bool]](
    frame: var FlatFrame, owner: Program, context: var Context, callbacks: HostCallbacks[Context,
        Reason],
    steps: ExecutionStepLimit, calls: HostCallLimit, pages: PageLimit): HostExecutionResult[Reason] =
  ## Keep one private engine frame across genuine callbacks; every public observation is immutable.
  var remaining = uint64(steps)
  var available = uint64(calls)
  let nativeBaseline = nativeOperations(frame)
  while true:
    # The engine counts attempted source instructions across every host continuation.
    runFlat(frame, remaining)
    remaining = frame.remaining
    if frame.reason != StepError.None:
      return executionResult[Reason](StepResult(status: frame.reason))
    if frame.exit != StepExit.Host: return executionResult[Reason](publishFrame(frame, owner,
        nativeBaseline = nativeBaseline))
    if available == 0: return executionResult[Reason](StepResult(
        status: StepError.HostCallLimitExceeded))
    dec available
    let memory = observeFlatHostMemory(frame)
    let captured = captureMachine(owner, memory, frame.info)
    if captured.error != MachineError.None:
      return executionResult[Reason](StepResult(status: StepError.InvalidMachine))
    let suspension = StepOutcome(engine: (if nativeOperations(frame) !=
        nativeBaseline: PvmBackend.Jit else: PvmBackend.Interpreted), kind: StepExit.Host,
        machine: captured.value,
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

proc runPreparedHost[Context; Reason: enum; Fallible: static[bool]](
    source: Machine, prepared: PreparedProgram, context: var Context, callbacks: HostCallbacks[
        Context, Reason],
    steps: ExecutionStepLimit, calls: HostCallLimit, plan: GasPlan,
        memo: GasMemo): HostExecutionResult[Reason] =
  ## Validate and create private memory before moving the exclusively leased executable cache.
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
  var created = prepareFlatMemoryFrame(data.plan, memory, cpu)
  if created.error != FlatError.None:
    return executionResult[Reason](StepResult(status: StepError.InvalidPreparedProgram))
  var frame = takeValue(created)
  let policy = selectFlatPrices(frame, plan, memo)
  if policy != StepError.None: return executionResult[Reason](StepResult(status: policy))
  restoreFlatStream(frame, data.stream)
  let answer = driveHostFrame[Context, Reason, Fallible](frame, owner, context, callbacks, steps,
      calls, data.limits.resources.pages)
  data.stream = takeFlatStream(frame)
  answer

proc hostSelected[Context; Reason: enum; Fallible: static[bool]](source: Machine,
    prepared: PreparedProgram, context: var Context, callbacks: HostCallbacks[Context, Reason],
        steps: ExecutionStepLimit,
    calls: HostCallLimit, plan: GasPlan = default(GasPlan), memo: GasMemo = default(
        GasMemo)): HostExecutionResult[Reason] =
  ## A shared owner remains busy throughout callbacks; every return path retires invocation state and releases it.
  let data = prepared.data
  if data == nil: return executionResult[Reason](StepResult(
      status: StepError.InvalidPreparedProgram))
  if data.busy: return executionResult[Reason](StepResult(status: StepError.PreparedProgramBusy))
  data.busy = true
  let answer = runPreparedHost[Context, Reason, Fallible](source, prepared, context, callbacks,
      steps, calls, plan, memo)
  data.busy = false
  answer

proc hostPolicy[Context; Reason: enum; Fallible: static[bool]](source: Machine,
    context: var Context, callbacks: HostCallbacks[Context, Reason], steps: ExecutionStepLimit,
        calls: HostCallLimit,
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
  hostSelected[Context, Reason, Fallible](source, prepared.value, context, callbacks, steps, calls,
      plan, memo)

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
  hostPolicy[Context, Reason, true](source, context, HostCallbacks[Context, Reason](
      fallible: handler), stepLimit, hostLimit, gasLimit)
proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, gasLimit: GasCycleLimit): StepResult =
  ## Ordinary callbacks use the same resident checked memory and only the new engine.
  responseResult(hostPolicy[Context, ResponseOnly, false](source, context, HostCallbacks[Context,
      ResponseOnly](response: handler), stepLimit, hostLimit, gasLimit))

proc executeWithHost*[Context; Reason: enum](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResult[Reason] {.nimcall,
        raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        prepared: PreparedProgram): HostExecutionResult[Reason] =
  ## Prepared callbacks share scalar executable facts while same-owner reentry remains refused.
  hostSelected[Context, Reason, true](source, prepared, context, HostCallbacks[Context, Reason](
      fallible: handler), stepLimit, hostLimit)
proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit,
        prepared: PreparedProgram): StepResult =
  ## Response-only prepared callers keep no private CPU, memory or callback in the reusable owner.
  responseResult(hostSelected[Context, ResponseOnly, false](source, prepared, context,
      HostCallbacks[Context, ResponseOnly](response: handler), stepLimit, hostLimit))

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
  hostPolicy[Context, Reason, true](source, context, HostCallbacks[Context, Reason](
      fallible: handler), stepLimit, hostLimit, settings.value.cycleLimit, plan)
proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, plan: GasPlan): StepResult =
  ## Pricing compatibility never selects a legacy evaluator.
  let settings = gasPlanInfo(plan)
  let owner = programOf(source)
  if settings.error != GasPlanError.None or owner.error != MachineError.None or not matchesProgram(
      plan, owner.value):
    return StepResult(status: StepError.InvalidGasPlan)
  responseResult(hostPolicy[Context, ResponseOnly, false](source, context, HostCallbacks[Context,
      ResponseOnly](response: handler), stepLimit, hostLimit, settings.value.cycleLimit, plan))

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
  hostPolicy[Context, Reason, true](source, context, HostCallbacks[Context, Reason](
      fallible: handler), stepLimit, hostLimit, settings.value.cycleLimit, memo = memo)
proc executeWithHost*[Context](source: Machine, context: var Context,
    handler: proc(context: var Context, suspension: StepOutcome): HostResponse {.nimcall, raises: [].},
    stepLimit: ExecutionStepLimit, hostLimit: HostCallLimit, memo: GasMemo): StepResult =
  ## Response-only lazy pricing preserves callback rejection and exact local source budgets.
  let settings = gasMemoInfo(memo)
  let owner = programOf(source)
  if settings.error != GasMemoError.None or owner.error != MachineError.None or not matchesProgram(
      memo, owner.value):
    return StepResult(status: StepError.InvalidGasMemo)
  responseResult(hostPolicy[Context, ResponseOnly, false](source, context, HostCallbacks[Context,
      ResponseOnly](response: handler), stepLimit, hostLimit, settings.value.cycleLimit, memo = memo))

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

proc backendAvailability*(selected: PvmBackend): StepError =
  ## Refuse unavailable explicit optional policies before any application resource, host or guest effect opens.
  if selected in [PvmBackend.Interpreted, PvmBackend.Jit]: return StepError.None
  let raw = @[0'u8, 0, 1, 0, 1]
  let source = decodeJamProgram(raw, CodeAddress(0), ProgramByteLimit(8), JumpCountLimit(0))
  if source.error != ProgramError.None: return StepError.BackendFailure
  let prepared = newPreparedProgram(source.value, defaultPreparedLimits(), selected)
  if prepared.error != PreparationError.None: return preparationFailure(prepared.error)
  StepError.None
