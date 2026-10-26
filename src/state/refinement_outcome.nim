# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute an opaque refinement bootstrap and publish only its normalized result, capped gas and exports.
## Source binding is internal; local preparation/host/engine refusals never become protocol work errors.

import ../pvm/[machine, step, gas, output, refinement_exports, host_fetch, inner_machines]
import ../codec/[composite, work_digest, work_report]
import ./[refinement_bootstrap, refinement_dispatch]

type
  RefinementInvocationError* {.pure.} = enum ## Tagged local refusals carry no output owner or partial gas/exports.
    Uninitialized, None, InvalidBootstrap, InvalidExecution, LimitExceeded, NotSuccess,
    BootstrapFailure, HostFailure, ExecutionFailure
  RefinementInvocationLimits* = object ## Each independent local budget preserves its own refusal stage.
    capture*: RefinementCaptureLimits
    copy*: MemoryByteLimit
    exports*: ExportLimits
    steps*: ExecutionStepLimit
    calls*: HostCallLimit
    backend*: PvmBackend ## Explicit engine applies equally to outer and nested guest execution.
    cycles*: GasCycleLimit
    output*: OutputByteLimit
    inner*: InnerMachineLimits
  RefinementInvocationInfo* = object ## Copied result metadata cannot replace source identity or immutable output storage.
    kind*: WorkKind
    service*: ServiceIndex
    core*: CoreIndex
    item*: FetchItemIndex
    gasUsed*: Gas
    exports*: ExportCount
    outputBytes*: uint64
  InvocationData = ref object ## Immutable acyclic final ownership retains original provenance and terminal-selected exports.
    bootstrap: PreparedRefinementBootstrap
    info: RefinementInvocationInfo
    exports: RefinementExports
    case hasOutput: bool
    of true:
      bytes: seq[byte]
    of false:
      discard # Protocol work errors carry no fabricated success byte buffer.
  RefinementInvocation* = object ## Default is invalid; Success with empty bytes is an explicit completed result.
    data: nil InvocationData
  RefinementInvocationResult*[T] = object ## Only the selected alternative exposes its completed value or typed failure detail.
    case status: RefinementInvocationError
    of None:
      completed: T
    of BootstrapFailure:
      bootstrapReason: RefinementBootstrapError
    of HostFailure:
      hostReason: RefinementDispatchError
    of ExecutionFailure:
      executionReason: StepError
    else:
      discard # Default and other local refusals have neither output nor invented detail fields.

func error*[T](outcome: RefinementInvocationResult[T]): RefinementInvocationError =
  ## Inspect the alternative without granting mutable discriminator access.
  outcome.status
func value*[T](outcome: RefinementInvocationResult[T]): T
    {.requires: outcome.status == RefinementInvocationError.None.} =
  ## Retain only complete selected success under optimized runtime contracts.
  outcome.completed
func bootstrapError*[T](outcome: RefinementInvocationResult[T]): RefinementBootstrapError
    {.requires: outcome.status == RefinementInvocationError.BootstrapFailure.} =
  ## Inspect only the original host-environment capture refusal.
  outcome.bootstrapReason
func hostError*[T](outcome: RefinementInvocationResult[T]): RefinementDispatchError
    {.requires: outcome.status == RefinementInvocationError.HostFailure.} =
  ## Inspect only the private callback's exact local refusal.
  outcome.hostReason
func executionError*[T](outcome: RefinementInvocationResult[T]): StepError
    {.requires: outcome.status == RefinementInvocationError.ExecutionFailure.} =
  ## Inspect only the engine's exact instruction or budget refusal.
  outcome.executionReason

proc refinementInfo*(invocation: RefinementInvocation): RefinementInvocationResult[
    RefinementInvocationInfo] =
  ## Copy complete normalized metadata; a missing owner never fabricates BAD or zero used gas.
  let data = invocation.data
  if data == nil: return RefinementInvocationResult[RefinementInvocationInfo](
      status: RefinementInvocationError.Uninitialized)
  RefinementInvocationResult[RefinementInvocationInfo](status: RefinementInvocationError.None,
      completed: data.info)
proc refinementOutput*(invocation: RefinementInvocation): RefinementInvocationResult[seq[byte]] =
  ## Extract an independent byte copy only for Success, including genuine readable/unreadable empty output.
  let data = invocation.data
  if data == nil: return RefinementInvocationResult[seq[byte]](
      status: RefinementInvocationError.Uninitialized)
  if not data.hasOutput: return RefinementInvocationResult[seq[byte]](
      status: RefinementInvocationError.NotSuccess)
  var copied = newSeq[byte](data.bytes.len)
  for index in 0..<copied.len: copied[index] = data.bytes[index] # No writable alias to saved output escapes.
  RefinementInvocationResult[seq[byte]](status: RefinementInvocationError.None, completed: copied)
proc refinementExports*(invocation: RefinementInvocation): RefinementInvocationResult[
    RefinementExports] =
  ## Retain the selected immutable sequence; work errors have a genuine initialized empty sequence.
  let data = invocation.data
  if data == nil: return RefinementInvocationResult[RefinementExports](
      status: RefinementInvocationError.Uninitialized)
  RefinementInvocationResult[RefinementExports](status: RefinementInvocationError.None,
      completed: data.exports)
proc refinementBootstrap*(invocation: RefinementInvocation): RefinementInvocationResult[
    PreparedRefinementBootstrap] =
  ## Retain the original source beside normalized results, independently of all caller handles.
  let data = invocation.data
  if data == nil: return RefinementInvocationResult[PreparedRefinementBootstrap](
      status: RefinementInvocationError.Uninitialized)
  RefinementInvocationResult[PreparedRefinementBootstrap](status: RefinementInvocationError.None,
      completed: data.bootstrap)

proc complete(bootstrap: PreparedRefinementBootstrap, source: RefinementBootstrapInfo,
    kind: WorkKind, used: Gas, exports: RefinementExports, bytes: seq[byte]):
    RefinementInvocationResult[RefinementInvocation] =
  ## Construct the one internally selected final owner; no public caller can substitute source/output tuples.
  let info = RefinementInvocationInfo(kind: kind, service: source.service, core: source.core,
    item: source.item, gasUsed: used, exports: exports.count,
    outputBytes: if kind == WorkKind.Success: uint64(bytes.len) else: 0'u64)
  let data = if kind == WorkKind.Success:
    InvocationData(bootstrap: bootstrap, info: info, exports: exports, hasOutput: true, bytes: bytes)
  else:
    InvocationData(bootstrap: bootstrap, info: info, exports: exports, hasOutput: false) # No error payload bytes.
  RefinementInvocationResult[RefinementInvocation](status: RefinementInvocationError.None,
    completed: RefinementInvocation(data: data))

proc runRefinementInvocation*(bootstrap: PreparedRefinementBootstrap, trace: openArray[byte],
    inputs: RefinementInputs, offset: ExportOffset, limits: RefinementInvocationLimits):
    RefinementInvocationResult[RefinementInvocation] =
  ## Run the original immutable CPU and host environment synchronously, then apply only Psi_M/Psi_R result rules.
  ## Borrowed trace/input descriptions stay stable until return; failures discard every scratch owner.
  template fail(reason: RefinementInvocationError) =
    return RefinementInvocationResult[RefinementInvocation](status: reason)
  let selected = bootstrap.bootstrapInfo
  if selected.error != RefinementBootstrapError.None: fail(
      RefinementInvocationError.InvalidBootstrap)
  let facts = selected.value
  let empty = captureRefinementExports(offset)
  case facts.status
  of RefinementCodeStatus.Bad:
    return complete(bootstrap, facts, WorkKind.Bad, Gas(0), empty, @[]) # No guest or external-input capture for BAD.
  of RefinementCodeStatus.Big:
    return complete(bootstrap, facts, WorkKind.Big, Gas(0), empty, @[]) # BIG likewise consumes no invocation gas.
  of RefinementCodeStatus.Ready:
    discard # Only a verified executable bootstrap can authorize host capture and execution.
  let captured = bootstrap.bootstrapHosts(trace, inputs, offset, limits.capture)
  if captured.error != RefinementBootstrapError.None:
    return RefinementInvocationResult[RefinementInvocation](
      status: RefinementInvocationError.BootstrapFailure,
      bootstrapReason: captured.error) # Preserve local capture/input policy details without a protocol result.
  let evaluated = executeRefinement(captured.value, limits.copy, limits.exports,
    limits.steps, limits.calls, limits.cycles, limits.inner, limits.backend)
  case evaluated.error
  of RefinementDispatchError.None:
    discard # Only a completed guest exit has terminal gas and an export selection to normalize.
  of RefinementDispatchError.ExecutionFailure:
    return RefinementInvocationResult[RefinementInvocation](
      status: RefinementInvocationError.ExecutionFailure,
      executionReason: evaluated.executionError) # Local engine exhaustion is never guest OutOfGas.
  else:
    return RefinementInvocationResult[RefinementInvocation](
      status: RefinementInvocationError.HostFailure,
      hostReason: evaluated.error) # Unsupported hosts and copy/export refusals publish no partial result.
  let executed = evaluated.value
  let cpu = executed.outcome.machine.machineInfo
  if cpu.error != MachineError.None: fail(RefinementInvocationError.InvalidExecution)
  let credit = uint64(facts.gas)
  let remaining = uint64(cpu.value.gas)
  if remaining > credit: fail(RefinementInvocationError.InvalidExecution) # Prove subtraction, never wrap or count terminal debt twice.
  let used = Gas(credit-remaining) # Canonical gas is max(signed gas,0); a deficit contributes no additional usage.
  case executed.outcome.exit
  of StepExit.OutOfGas:
    complete(bootstrap, facts, WorkKind.OutOfGas, used, empty, @[]) # Preserve unspent credit when block pricing refused before debit.
  of StepExit.Panic, StepExit.Fault:
    complete(bootstrap, facts, WorkKind.Panic, used, empty, @[]) # Physical fault follows Psi_M's ordinary panic branch.
  of StepExit.Halt:
    let returned = captureOutput(executed.outcome, limits.output)
    case returned.error
    of OutputError.None:
      complete(bootstrap, facts, WorkKind.Success, used, executed.exports,
          returned.value) # Empty output still retains halt exports.
    of OutputError.LimitExceeded:
      fail(RefinementInvocationError.LimitExceeded) # Local output policy cannot become protocol Oversize or truncate bytes.
    else:
      fail(RefinementInvocationError.InvalidExecution) # A malformed halt owner cannot fabricate successful empty output.
  else:
    fail(RefinementInvocationError.InvalidExecution) # Continued/host suspensions are not completed invocation outputs.
