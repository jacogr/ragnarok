# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute pinned Psi_I from an original package's historical authorizer code and retain immutable provenance.
## Local policy refusals are distinct from protocol work errors; report composition/publication is separate.

import ../../lib/logging

import ../../codec/[bounded, composite]
import ../../codec/work/[package as work_package, digest as work_digest, report as work_report]
import ../../codec/state/service_values as state_service_values
import ../../chain/parameters
import ../../crypto/primitives
import ../../pvm/[machine, program, initialize, step, gas, output, host_gas, host_log, host_heap, host_fetch]
import ../store
import ../refinement/lookup as refinement_lookup

type
  AuthorizationHostError* {.pure.} = enum ## Callback refusals cannot fabricate a charged reply or guest work error.
    InvalidContext, InvalidMemory, LimitExceeded
  AuthorizationInvocationError* {.pure.} = enum ## Every default/refused alternative has no invocation output or partial progress.
    Uninitialized, None, InvalidSelection, InvalidParameters, InvalidState, MalformedCode,
    BackendFailure, LimitExceeded, InvalidExecution, NotSuccess, LookupFailure,
    InitializationFailure, FetchFailure, HostFailure, ExecutionFailure
  AuthorizationInvocationLimits* = object ## Finite preparation/capture/execution/copy policies are independent from consensus constants.
    preimage*: ByteLimit
    initialization*: InitializationLimits
    package*: FetchPackageLimit
    encoding*: FetchEncodingLimit
    copy*: MemoryByteLimit
    logging*: LogWriter
    steps*: ExecutionStepLimit
    calls*: HostCallLimit
    backend*: PvmBackend ## Explicit guest engine, independent of every local resource ceiling.
    cycles*: GasCycleLimit
    output*: OutputByteLimit
  AuthorizationInvocationInfo* = object ## Copied final facts cannot replace retained code, source owners, core or trace.
    kind*: WorkKind
    core*: CoreIndex
    host*: ServiceIndex
    anchor*: LookupSlot
    gasUsed*: Gas
    traceBytes*: uint64
  AuthorizationSource = object ## Original complete state, canonical package and configured parameters share no writable storage.
    state: StateStoreSnapshot
    package: OwnedWorkPackage
    parameters: Parameters
    core: CoreIndex
    host: ServiceIndex
    anchor: LookupSlot
  AuthorizationData = ref object ## Immutable acyclic final ownership has bytes only for actual Success.
    source: AuthorizationSource
    info: AuthorizationInvocationInfo
    case hasTrace: bool
    of true:
      trace: seq[byte]
    of false:
      discard # Protocol errors contain no fabricated successful byte payload.
  AuthorizationInvocation* = object ## Default is invalid; a genuine empty Success has an explicit owner.
    data: nil AuthorizationData
  AuthorizationInvocationResult*[T] = object ## Private alternatives expose only complete success or the selected local stage detail.
    case status: AuthorizationInvocationError
    of None:
      completed: T
    of LookupFailure:
      lookupReason: HistoricalLookupError
    of InitializationFailure:
      initializationReason: InitializationError
    of FetchFailure:
      fetchReason: FetchError
    of HostFailure:
      hostReason: AuthorizationHostError
    of ExecutionFailure:
      executionReason: StepError
    else:
      discard # Neither default nor simple local errors contain a partial source/trace or unrelated reason.
  AuthorizationContext = object ## One synchronous run binds fetch and heap responses to its own initialized machine.
    logger: LogWriter
    fetch: FetchContext
    first, past: PageIndex
    copy: MemoryByteLimit

func error*[T](outcome: AuthorizationInvocationResult[T]): AuthorizationInvocationError =
  ## Inspect the selected alternative without writable discriminator access.
  outcome.status
func value*[T](outcome: AuthorizationInvocationResult[T]): T
    {.requires: outcome.status == AuthorizationInvocationError.None.} =
  ## Extract only complete selected success under checked optimized contracts.
  outcome.completed
func lookupError*[T](outcome: AuthorizationInvocationResult[T]): HistoricalLookupError
    {.requires: outcome.status == AuthorizationInvocationError.LookupFailure.} =
  ## Inspect only historical lookup's original local refusal.
  outcome.lookupReason
func initializationError*[T](outcome: AuthorizationInvocationResult[T]): InitializationError
    {.requires: outcome.status == AuthorizationInvocationError.InitializationFailure.} =
  ## Inspect only initialization's exact refusal rather than a fabricated work error.
  outcome.initializationReason
func fetchError*[T](outcome: AuthorizationInvocationResult[T]): FetchError
    {.requires: outcome.status == AuthorizationInvocationError.FetchFailure.} =
  ## Inspect only fetch-environment capture failure.
  outcome.fetchReason
func hostError*[T](outcome: AuthorizationInvocationResult[T]): AuthorizationHostError
    {.requires: outcome.status == AuthorizationInvocationError.HostFailure.} =
  ## Inspect only a callback's exact local refusal.
  outcome.hostReason
func executionError*[T](outcome: AuthorizationInvocationResult[T]): StepError
    {.requires: outcome.status == AuthorizationInvocationError.ExecutionFailure.} =
  ## Inspect only engine budget/instruction refusal, without a terminal CPU.
  outcome.executionReason
proc authorizationInfo*(invocation: AuthorizationInvocation): AuthorizationInvocationResult[
    AuthorizationInvocationInfo] =
  ## Copy normalized facts only from a complete owner.
  let data = invocation.data
  if data == nil: return AuthorizationInvocationResult[AuthorizationInvocationInfo](
      status: AuthorizationInvocationError.Uninitialized)
  AuthorizationInvocationResult[AuthorizationInvocationInfo](
      status: AuthorizationInvocationError.None, completed: data.info)
proc authorizationPackage*(invocation: AuthorizationInvocation): AuthorizationInvocationResult[
    OwnedWorkPackage] =
  ## Retain exactly the original package used for code selection, host capture and execution.
  let data = invocation.data
  if data == nil: return AuthorizationInvocationResult[OwnedWorkPackage](
      status: AuthorizationInvocationError.Uninitialized)
  AuthorizationInvocationResult[OwnedWorkPackage](status: AuthorizationInvocationError.None,
      completed: data.source.package)
proc authorizationState*(invocation: AuthorizationInvocation): AuthorizationInvocationResult[
    StateStoreSnapshot] =
  ## Preserve the actual complete source map for later source-bound report composition.
  let data = invocation.data
  if data == nil: return AuthorizationInvocationResult[StateStoreSnapshot](
      status: AuthorizationInvocationError.Uninitialized)
  AuthorizationInvocationResult[StateStoreSnapshot](status: AuthorizationInvocationError.None,
      completed: data.source.state)
proc authorizationParameters*(invocation: AuthorizationInvocation): AuthorizationInvocationResult[Parameters] =
  ## Retain the original parameter snapshot rather than a caller's substitute during later composition/replay.
  let data = invocation.data
  if data == nil: return AuthorizationInvocationResult[Parameters](
      status: AuthorizationInvocationError.Uninitialized)
  AuthorizationInvocationResult[Parameters](status: AuthorizationInvocationError.None,
      completed: data.source.parameters)
proc authorizationTrace*(invocation: AuthorizationInvocation): AuthorizationInvocationResult[seq[byte]] =
  ## Return an independent Success-only byte copy, including explicit readable/unreadable empty output.
  let data = invocation.data
  if data == nil: return AuthorizationInvocationResult[seq[byte]](
      status: AuthorizationInvocationError.Uninitialized)
  if not data.hasTrace: return AuthorizationInvocationResult[seq[byte]](
      status: AuthorizationInvocationError.NotSuccess)
  var bytes = newSeq[byte](data.trace.len)
  for index in 0..<bytes.len: bytes[index] = data.trace[index] # No mutable alias to retained bytes escapes.
  AuthorizationInvocationResult[seq[byte]](status: AuthorizationInvocationError.None,
      completed: bytes)

proc complete(source: AuthorizationSource, kind: WorkKind, used: Gas, trace: seq[byte]):
    AuthorizationInvocationResult[AuthorizationInvocation] =
  ## Select one internally constructed final variant; public callers cannot substitute CPU/result/source tuples.
  let info = AuthorizationInvocationInfo(kind: kind, core: source.core, host: source.host,
    anchor: source.anchor,
    gasUsed: used, traceBytes: if kind == WorkKind.Success: uint64(trace.len) else: 0'u64)
  let data = if kind == WorkKind.Success:
    AuthorizationData(source: source, info: info, hasTrace: true, trace: trace)
  else:
    AuthorizationData(source: source, info: info, hasTrace: false) # Work errors have no successful trace storage.
  AuthorizationInvocationResult[AuthorizationInvocation](status: AuthorizationInvocationError.None,
    completed: AuthorizationInvocation(data: data))
proc dispatch(context: var AuthorizationContext, stopped: StepOutcome): HostResult[
    AuthorizationHostError] =
  ## Dispatch Psi_I's general hosts and JIP-1 logging; other IDs retain charged WHAT semantics.
  let info = stopped.machine.machineInfo
  let captured = stopped.machine.memoryOf
  if info.error != MachineError.None: return hostFailure(AuthorizationHostError.InvalidContext)
  if captured.error != MachineError.None: return hostFailure(AuthorizationHostError.InvalidMemory)
  let cpu = info.value
  let memory = captured.value
  case uint64(stopped.hostCall)
  of 0:
    hostSuccess[AuthorizationHostError](gasHostResponse(cpu.gas, cpu.registers, memory))
  of 1:
    let grown = growHeapResponse(context.first, context.past, cpu.gas, cpu.registers, memory)
    if grown.kind == HostResultKind.Response: return hostSuccess[AuthorizationHostError](grown.value)
    hostFailure(if grown.failure == HeapHostError.LimitExceeded: AuthorizationHostError.LimitExceeded
      else: AuthorizationHostError.InvalidContext) # Local page capacity never becomes protocol OOG.
  of 2:
    let fetched = fetchContextResponse(context.fetch, cpu.gas, cpu.registers, memory, context.copy)
    if fetched.error == FetchError.None: return hostSuccess[AuthorizationHostError](fetched.value)
    hostFailure(if fetched.error == FetchError.LimitExceeded: AuthorizationHostError.LimitExceeded
      else: AuthorizationHostError.InvalidContext) # No partial fetch response escapes a local refusal.
  of 100:
    # JIP-1 uses its explicitly adopted ten-gas price, independent of the GP unknown fallback.
    hostSuccess[AuthorizationHostError](logHostResponse(cpu.gas, cpu.registers, memory,
        context.logger))
  else:
    hostSuccess[AuthorizationHostError](unknownHostResponse(cpu.gas, cpu.registers, memory))

proc runAuthorizationInvocation*(state: StateStoreSnapshot, package: OwnedWorkPackage,
    core: CoreIndex, parameters: Parameters, limits: AuthorizationInvocationLimits):
    AuthorizationInvocationResult[AuthorizationInvocation] =
  ## Resolve, initialize and execute only this source's authorizer; every refusal retires all private scratch owners.
  template fail(reason: AuthorizationInvocationError) =
    return AuthorizationInvocationResult[AuthorizationInvocation](status: reason)
  if not parameters.valid: fail(AuthorizationInvocationError.InvalidParameters)
  let described = package.workPackageInfo
  if described.error != PackageError.None: fail(AuthorizationInvocationError.InvalidSelection)
  if uint64(core) >= 65536 or uint64(core) >= parameters.get(coreCount):
    fail(AuthorizationInvocationError.InvalidSelection) # Prove the full E2 and chain domains before byte narrowing.
  let source = AuthorizationSource(state: state, package: package, parameters: parameters,
    core: core,
    host: ServiceIndex(uint32(described.value.host)), anchor: described.value.context.lookupSlot)
  let captured = captureHistoricalLookup(state, source.host, source.anchor)
  if captured.error != HistoricalLookupError.None:
    return AuthorizationInvocationResult[AuthorizationInvocation](
      status: AuthorizationInvocationError.LookupFailure,
      lookupReason: captured.error)
  let code = historicalPreimage(captured.value, source.host, ServicePreimageHash(array[32, byte](
      described.value.codeHash)))
  if code.error != HistoricalLookupError.None:
    return AuthorizationInvocationResult[AuthorizationInvocation](
      status: AuthorizationInvocationError.LookupFailure,
      lookupReason: code.error)
  if not code.value.present: return complete(source, WorkKind.Bad, Gas(0), @[]) # Absence needs neither code copying nor execution.
  if uint64(code.value.value.byteLength) > uint64(limits.preimage): fail(
      AuthorizationInvocationError.LimitExceeded)
  let preimage = code.value.value.bytes
  let hash = blake2b256(preimage)
  if hash.error != CryptoError.None: fail(AuthorizationInvocationError.BackendFailure)
  if array[32, byte](hash.value) != array[32, byte](described.value.codeHash):
    fail(AuthorizationInvocationError.InvalidState) # A synthetic map under the wrong key cannot certify authorization code.
  let metadata = decodeBytesBorrowed(preimage, ByteLimit(uint64(preimage.len)))
  if metadata.error != ContainerError.None: fail(AuthorizationInvocationError.MalformedCode)
  let start = metadata.consumed
  let size = preimage.len-start # Canonical metadata parsing proves the subtraction and exact suffix extent.
  if size > 64000: return complete(source, WorkKind.Big, Gas(0), @[]) # The code suffix, not metadata/preimage size, selects BIG.
  if uint64(size) > uint64(limits.initialization.envelope): fail(
      AuthorizationInvocationError.LimitExceeded)
  var envelope = newSeq[byte](size)
  for index in 0..<size: envelope[index] = preimage[
      start+index] # Bound copying before allocation, preserving exact authenticated suffix.
  let arguments = [byte(uint64(core) and 255), byte((uint64(core) shr 8) and 255)]
  let initialized = initializeMachine(envelope, arguments, CodeAddress(0), MachineGas(50000000),
      limits.initialization)
  if initialized.error != InitializationError.None:
    return AuthorizationInvocationResult[AuthorizationInvocation](
      status: AuthorizationInvocationError.InitializationFailure,
      initializationReason: initialized.error)
  let base = captureFetchContext(FetchPresence.Absent, default(FetchEntropy), FetchPresence.Absent,
      [], FetchTraceLimit(0)).value
  let configured = base.withFetchParameters(parameters)
  if configured.error != FetchError.None:
    return AuthorizationInvocationResult[AuthorizationInvocation](
        status: AuthorizationInvocationError.FetchFailure, fetchReason: configured.error)
  let fetched = configured.value.withFetchPackage(FetchPresence.Present, package, limits.package,
      limits.encoding)
  if fetched.error != FetchError.None:
    return AuthorizationInvocationResult[AuthorizationInvocation](
        status: AuthorizationInvocationError.FetchFailure, fetchReason: fetched.error)
  var ro = 0'u64
  var stack = 0'u64
  for index in 0..<3:
    ro = ro or (uint64(envelope[index]) shl (8*index))
    stack = stack or (uint64(envelope[8+index]) shl (
        8*index)) # Initialized E3 values prove zone rounding and page narrowing fit.
  var context = AuthorizationContext(logger: limits.logging, fetch: fetched.value,
    copy: limits.copy,
    first: PageIndex(uint32(32+((ro+65535) div 65536)*16)),
    past: PageIndex(uint32((0xfefd0000'u64-((stack+65535) div 65536)*65536) div 4096)))
  let executed = executeWithHost(initialized.value, context, dispatch, limits.steps, limits.calls,
      limits.cycles, limits.backend)
  case executed.error
  of HostExecutionError.None:
    discard # Only a terminal guest outcome has gas and a result suitable for Psi_M normalization.
  of HostExecutionError.ExecutionFailure:
    return AuthorizationInvocationResult[AuthorizationInvocation](
      status: AuthorizationInvocationError.ExecutionFailure,
      executionReason: executed.executionError)
  of HostExecutionError.HostFailure:
    return AuthorizationInvocationResult[AuthorizationInvocation](
        status: AuthorizationInvocationError.HostFailure, hostReason: executed.hostError)
  else:
    fail(AuthorizationInvocationError.InvalidExecution)
  let terminal = executed.value
  let cpu = terminal.machine.machineInfo
  if cpu.error != MachineError.None or uint64(cpu.value.gas) > 50000000:
    fail(AuthorizationInvocationError.InvalidExecution) # Prove subtraction; terminal deficit contributes no extra consumption.
  let used = Gas(50000000'u64-uint64(cpu.value.gas))
  case terminal.exit
  of StepExit.OutOfGas:
    complete(source, WorkKind.OutOfGas, used, @[])
  of StepExit.Panic, StepExit.Fault:
    complete(source, WorkKind.Panic, used, @[])
  of StepExit.Halt:
    let returned = captureOutput(terminal, limits.output)
    if returned.error == OutputError.LimitExceeded: fail(AuthorizationInvocationError.LimitExceeded)
    if returned.error != OutputError.None: fail(AuthorizationInvocationError.InvalidExecution)
    complete(source, WorkKind.Success, used, returned.value)
  else:
    fail(AuthorizationInvocationError.InvalidExecution) # Host/Continue are never completed invocation traces.
