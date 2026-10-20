# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture one immutable refinement host environment and run its supported hosts with bounded execution.
## Caller supplies trusted initialized CPU/heap and authenticated input bytes; this is not a Psi_R certificate.

import ../pvm/[machine, step, gas, host_gas, host_heap, host_fetch, refinement_exports, inner_machines]
import ../codec/[bounded, work_package, work_digest]
import ../chain/parameters
import ./[store, refinement_lookup]

type
  RefinementDispatchError* {.pure.} = enum ## Local failures expose no partial CPU, output or export history.
    Uninitialized, None, InvalidMachine, InvalidContext, InvalidInputs, InvalidParameters,
    LimitExceeded, UnsupportedHostCall, ExecutionFailure, MalformedState, BackendFailure
  RefinementInputs* = object ## Borrowed all-item input tables; callers authenticate bytes against the package before capture.
    extrinsics*: seq[seq[seq[byte]]]
    imports*: seq[seq[FetchSegment]]
  RefinementCaptureLimits* = object ## Independent finite capture budgets bound trace, package snapshots and external data.
    trace*: FetchTraceLimit
    package*: FetchPackageLimit
    encoding*: FetchEncodingLimit
    inputs*: FetchInputLimit
  RefinementHeapBounds* = object ## Initialization-derived trusted geometry, not guest-supplied addresses.
    first*, past*: PageIndex
  RefinementData = ref object ## Immutable acyclic provenance keeps all captured inputs beside their original CPU.
    machine: Machine
    fetch: FetchContext
    lookup: HistoricalLookupContext
    heap: RefinementHeapBounds
    offset: ExportOffset
  PreparedRefinementExecution* = object ## A replayable caller-prepared environment, without code eligibility or block authority.
    data: nil RefinementData
  RefinementOutcome* = object ## Raw engine exit with terminal-selected exports; return-buffer/gas normalization is separate.
    outcome*: StepOutcome
    exports*: RefinementExports
  RefinementDispatchResult*[T] = object ## Default/refused alternatives cannot fabricate prepared or executed successors.
    case status: RefinementDispatchError
    of None:
      completed: T
    of ExecutionFailure:
      reason: StepError
    else:
      discard # No partially completed owner or scratch data on failure.
  DispatchContext = object ## Only one synchronous run mutates this private export selection.
    source: RefinementData
    exports: RefinementExports
    copyLimit: MemoryByteLimit
    exportLimits: ExportLimits
    machines: InnerMachines

func error*[T](outcome: RefinementDispatchResult[T]): RefinementDispatchError =
  ## Inspect the alternative without writable tag access.
  outcome.status
func value*[T](outcome: RefinementDispatchResult[T]): T
    {.requires: outcome.status == RefinementDispatchError.None.} =
  ## Extract only a completely prepared or executed value.
  outcome.completed
func executionError*[T](outcome: RefinementDispatchResult[T]): StepError
    {.requires: outcome.status == RefinementDispatchError.ExecutionFailure.} =
  ## Retain the engine's exact budget/instruction refusal without a fabricated guest outcome.
  outcome.reason

proc prepareRefinementExecution*(initial: Machine, state: StateStoreSnapshot,
    package: OwnedWorkPackage, item: FetchItemIndex, parameters: Parameters,
    trace: openArray[byte], inputs: RefinementInputs, heap: RefinementHeapBounds,
    offset: ExportOffset, limits: RefinementCaptureLimits):
    RefinementDispatchResult[PreparedRefinementExecution] =
  ## Bind lookup identity and all fetch selections to one validated owned package/current item.
  ## Borrowed input tables remain stable until return; no caller-owned mutable data escapes capture.
  template fail(reason: RefinementDispatchError) =
    return RefinementDispatchResult[PreparedRefinementExecution](status: reason)
  let cpu = initial.machineInfo
  let memory = initial.memoryOf
  if cpu.error != MachineError.None or memory.error != MachineError.None:
    fail(RefinementDispatchError.InvalidMachine) # No default CPU may authorize an execution environment.
  if uint64(cpu.value.gasDeficit) != 0:
    fail(RefinementDispatchError.InvalidMachine) # A negative terminal gas owner cannot restart as a fresh invocation.
  if memory.value.writablePageCount(heap.first, heap.past).error != MachineError.None:
    fail(RefinementDispatchError.InvalidContext) # Validate nominal geometry before any host can use it.
  if not parameters.valid: fail(RefinementDispatchError.InvalidParameters)
  let described = package.workPackageInfo
  if described.error != PackageError.None: fail(RefinementDispatchError.InvalidContext)
  if uint64(item) >= uint64(described.value.items): fail(RefinementDispatchError.InvalidInputs)
  if inputs.extrinsics.len != described.value.items or inputs.imports.len != described.value.items:
    fail(RefinementDispatchError.InvalidInputs) # Exact tables prevent absent rows from becoming protocol NONE.
  for index in 0..<described.value.items:
    let selected = package.workItemAt(index).value
    let info = selected.workItemInfo.value
    if inputs.extrinsics[index].len != info.extrinsics or inputs.imports[index].len != info.imports:
      fail(RefinementDispatchError.InvalidInputs) # Preflight manifest cardinalities before payload copying.
    for extrinsic in 0..<info.extrinsics:
      if uint64(inputs.extrinsics[index][extrinsic].len) != uint64(selected.extrinsicAt(
          extrinsic).value.length):
        fail(RefinementDispatchError.InvalidInputs) # Hash authentication remains the caller's separate obligation.
  let selected = package.workItemAt(int(uint64(item))).value.workItemInfo.value
  let lookup = captureHistoricalLookup(state, selected.service, described.value.context.lookupSlot)
  if lookup.error != HistoricalLookupError.None: fail(RefinementDispatchError.InvalidContext)
  let base = captureFetchContext(FetchPresence.Present, FetchEntropy(default(array[32, byte])),
    FetchPresence.Present, trace, limits.trace)
  if base.error == FetchError.LimitExceeded: fail(RefinementDispatchError.LimitExceeded)
  if base.error != FetchError.None: fail(RefinementDispatchError.InvalidContext)
  let configured = base.value.withFetchParameters(parameters)
  if configured.error != FetchError.None: fail(RefinementDispatchError.InvalidParameters)
  let attached = configured.value.withFetchPackage(FetchPresence.Present, package, limits.package,
      limits.encoding)
  if attached.error == FetchError.LimitExceeded: fail(RefinementDispatchError.LimitExceeded)
  if attached.error != FetchError.None: fail(RefinementDispatchError.InvalidContext)
  let fetched = attached.value.withFetchInputs(FetchInputs(
    extrinsicsPresence: FetchPresence.Present,
    importsPresence: FetchPresence.Present, currentPresence: FetchPresence.Present, current: item,
    extrinsics: inputs.extrinsics, imports: inputs.imports), limits.inputs)
  if fetched.error == FetchError.LimitExceeded: fail(RefinementDispatchError.LimitExceeded)
  if fetched.error != FetchError.None: fail(RefinementDispatchError.InvalidInputs)
  RefinementDispatchResult[PreparedRefinementExecution](status: RefinementDispatchError.None,
    completed: PreparedRefinementExecution(data: RefinementData(machine: initial,
      fetch: fetched.value,
      lookup: lookup.value, heap: heap, offset: offset)))

proc dispatch(context: var DispatchContext, stopped: StepOutcome): HostResult[
    RefinementDispatchError] {.raises: [].} =
  ## The engine supplies a genuine suspension; all host effects remain private until the complete run succeeds.
  let cpu = stopped.machine.machineInfo.value
  let memory = stopped.machine.memoryOf.value
  case uint64(stopped.hostCall)
  of 0:
    hostSuccess[RefinementDispatchError](gasHostResponse(cpu.gas, cpu.registers, memory)) # Shared gas semantics.
  of 1:
    let grown = growHeapResponse(context.source.heap.first, context.source.heap.past, cpu.gas,
        cpu.registers, memory)
    if grown.kind == HostResultKind.Response: return hostSuccess[RefinementDispatchError](grown.value)
    hostFailure(if grown.failure == HeapHostError.LimitExceeded: RefinementDispatchError.LimitExceeded
      else: RefinementDispatchError.InvalidContext) # Translate only local refusal; never change protocol OOG.
  of 2:
    let fetched = fetchContextResponse(context.source.fetch, cpu.gas, cpu.registers, memory,
        context.copyLimit)
    if fetched.error == FetchError.None: return hostSuccess[RefinementDispatchError](fetched.value)
    hostFailure(if fetched.error == FetchError.LimitExceeded: RefinementDispatchError.LimitExceeded
      else: RefinementDispatchError.InvalidContext) # No synthetic absence on a capture/copy refusal.
  of 7:
    let looked = historicalLookupResponse(context.source.lookup, cpu.gas, cpu.registers, memory,
        context.copyLimit)
    case looked.error
    of HistoricalLookupError.None:
      hostSuccess[RefinementDispatchError](looked.value) # Preserve charged panic, absence and exact OOG debt.
    of HistoricalLookupError.MalformedState:
      hostFailure(RefinementDispatchError.MalformedState)
    of HistoricalLookupError.BackendFailure:
      hostFailure(RefinementDispatchError.BackendFailure)
    of HistoricalLookupError.LimitExceeded:
      hostFailure(RefinementDispatchError.LimitExceeded)
    else:
      hostFailure(RefinementDispatchError.InvalidContext)
  of 8:
    let exported = exportResponse(context.exports, cpu.gas, cpu.registers, memory,
        context.exportLimits)
    if exported.error == RefinementExportError.None:
      let selected = exported.value
      context.exports = selected.exports # Completed response and successor belong to the same host transition.
      return hostSuccess[RefinementDispatchError](selected.response)
    hostFailure(if exported.error == RefinementExportError.LimitExceeded: RefinementDispatchError.LimitExceeded
      else: RefinementDispatchError.InvalidContext) # No partially appended output on local failure.
  of 9..12, 14:
    let changed = if uint64(stopped.hostCall) == 9:
      createInnerMachine(context.machines, cpu.gas, cpu.registers, memory)
    elif uint64(stopped.hostCall) == 10:
      innerPeekResponse(context.machines, cpu.gas, cpu.registers, memory, context.copyLimit)
    elif uint64(stopped.hostCall) == 11:
      innerPokeResponse(context.machines, cpu.gas, cpu.registers, memory, context.copyLimit)
    elif uint64(stopped.hostCall) == 12:
      innerPagesResponse(context.machines, cpu.gas, cpu.registers, memory)
    else:
      expungeInnerMachine(context.machines, cpu.gas, cpu.registers,
          memory) # Every implemented inner host uses one invocation-local map.
    if changed.error == InnerMachineError.None:
      context.machines = changed.value.machines
      return hostSuccess[RefinementDispatchError](
          changed.value.response) # Response and immutable map move together.
    hostFailure(if changed.error == InnerMachineError.LimitExceeded: RefinementDispatchError.LimitExceeded
      else: RefinementDispatchError.InvalidContext) # A local capture refusal cannot become protocol HUH/FULL.
  of 13:
    hostFailure(RefinementDispatchError.UnsupportedHostCall) # Known inner-machine hosts are not protocol-unknown identifiers.
  else:
    hostSuccess[RefinementDispatchError](unknownHostResponse(cpu.gas, cpu.registers,
        memory)) # Includes accumulation-only IDs.

proc executeRefinement*(prepared: PreparedRefinementExecution, copyLimit: MemoryByteLimit,
    exportLimits: ExportLimits, steps: ExecutionStepLimit, calls: HostCallLimit,
    cycles: GasCycleLimit, inner: InnerMachineLimits = default(InnerMachineLimits)):
    RefinementDispatchResult[RefinementOutcome] =
  ## Replay the original immutable CPU with fresh exports; refuse atomically without exposing callback progress.
  let data = prepared.data
  if data == nil: return RefinementDispatchResult[RefinementOutcome](
      status: RefinementDispatchError.InvalidContext)
  let empty = captureRefinementExports(data.offset)
  var context = DispatchContext(source: data, exports: empty, copyLimit: copyLimit,
      exportLimits: exportLimits, machines: captureInnerMachines(inner))
  let evaluated = executeWithHost(data.machine, context, dispatch, steps, calls, cycles)
  case evaluated.error
  of HostExecutionError.None:
    let selected = evaluated.value
    let exports = if selected.exit == StepExit.Halt: context.exports else: empty # Failed guests publish no exports.
    RefinementDispatchResult[RefinementOutcome](status: RefinementDispatchError.None,
      completed: RefinementOutcome(outcome: selected, exports: exports))
  of HostExecutionError.ExecutionFailure:
    RefinementDispatchResult[RefinementOutcome](status: RefinementDispatchError.ExecutionFailure,
      reason: evaluated.executionError) # Preserve the exact local budget/instruction reason.
  of HostExecutionError.HostFailure:
    RefinementDispatchResult[RefinementOutcome](status: evaluated.hostError) # Scratch exports die with this run.
  else:
    RefinementDispatchResult[RefinementOutcome](status: RefinementDispatchError.InvalidContext)
