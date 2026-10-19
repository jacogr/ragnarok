# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute a prepared accumulation CPU with its own fetch environment and implemented general calls.
## Guarded results separate guest outcomes, engine refusals and unavailable host functionality.
## Retains checkpoint/yield implications beside guest outcomes; Psi_A normalization/publication remain open.

import ../chain/parameters
import ../pvm/[machine, step, gas, host_gas, host_fetch]
import ../codec/state_outputs
import ./[accumulation_machine, accumulation_fetch, accumulation_context, accumulation_effects]

type
  ## Local preparation/host refusals never impersonate guest panic, NONE or WHAT.
  AccumulationDispatchError* {.pure.} = enum
    Uninitialized, None, InvalidMachine, InvalidParameters, LimitExceeded, InvalidContext,
    UnsupportedHostCall, ExecutionFailure
  ## Success alone retains a CPU outcome; engine failure carries only its enum-valued reason.
  AccumulationDispatchResult* = object
    case status: AccumulationDispatchError
    of None:
      completed: StepOutcome                # Immutable successor; no reference back to this result.
      completedEffects: AccumulationEffects # Both dimensions belong to this exact execution.
    of ExecutionFailure:
      reason: StepError                     # No partial machine or progress is exposed on refusal.
    else:
      discard                               # Other failures contain only the outer reason.
  ## Callback-local immutable fetch ownership cannot be substituted by the guest or caller.
  DispatchContext = object
    fetch: FetchContext
    copyLimit: MemoryByteLimit
    effects: AccumulationEffects

## Inspect the selected alternative without granting mutable access to its discriminator.
func error*(outcome: AccumulationDispatchResult): AccumulationDispatchError = outcome.status
## Retain a completed guest outcome independently of all preparation handles.
func value*(outcome: AccumulationDispatchResult): StepOutcome {.inline,
    requires: outcome.status == AccumulationDispatchError.None.} = outcome.completed
## Retain both current implication dimensions only after complete guest execution succeeds.
## A guest panic/OOG is a completed outcome; local engine/host refusals expose neither dimension.
func effects*(outcome: AccumulationDispatchResult): AccumulationEffects {.inline,
    requires: outcome.status == AccumulationDispatchError.None.} = outcome.completedEffects
## Inspect the original execution-budget or instruction refusal without a fabricated guest result.
func executionError*(outcome: AccumulationDispatchResult): StepError {.inline,
    requires: outcome.status == AccumulationDispatchError.ExecutionFailure.} = outcome.reason

## Charge checkpoint/yield before reading memory or changing implications; debt preserves exact magnitude.
## Effects are callback-local immutable versions, discarded if later execution refuses locally.
proc effectResponse(context: var DispatchContext, cpu: MachineInfo, memory: Memory,
    checkpoint: bool): HostResult[AccumulationDispatchError] {.raises: [].} =
  let cost = (if checkpoint: 103'u64 else: 98'u64) # GP definitions.tex M_C and M_Taurus.
  let available = uint64(cpu.gas)
  var response = HostResponse(action: HostAction.Continue, gas: MachineGas(0),
    gasDeficit: GasDeficit(0), registers: cpu.registers, memory: memory)
  if available < cost:
    # General affordability failure precedes all row-specific mutations, including checkpoint's assignment.
    response.action = HostAction.OutOfGas
    response.gasDeficit = GasDeficit(cost-available)
    return hostSuccess[AccumulationDispatchError](response)
  response.gas = MachineGas(available-cost)
  if checkpoint:
    # Y'=X retains the complete supported current context; r7 reports post-charge gas.
    let changed = checkpointAccumulationEffects(context.effects)
    if changed.error != AccumulationEffectError.None:
      return hostFailure(AccumulationDispatchError.InvalidContext) # No fabricated implication owner.
    context.effects = changed.value
    response.registers[7] = RegisterValue(available-cost)
  else:
    # Yield reads a natural 32-byte guest interval; full-width pointers never wrap into accessible RAM.
    let copied = readBytes(memory, MemoryAddress(uint64(cpu.registers[7])), MemoryLength(32),
      context.copyLimit)
    case copied.error
    of MachineError.None:
      var bytes = default(array[32, byte])
      for i in 0..<32:
        bytes[i] = copied.value[i] # A complete successful read supplies every commitment byte.
      let changed = recordAccumulationYield(context.effects, OutputCommitment(bytes))
      if changed.error != AccumulationEffectError.None:
        return hostFailure(AccumulationDispatchError.InvalidContext) # No partial effect publication.
      context.effects = changed.value
      response.registers[7] = RegisterValue(0) # OK, including an all-zero present commitment.
    of MachineError.Fault, MachineError.InvalidRange:
      response.action = HostAction.Panic # Charged panic preserves r7 and both implication versions.
    of MachineError.LimitExceeded:
      return hostFailure(AccumulationDispatchError.LimitExceeded) # Local copy policy is not guest panic.
    else:
      return hostFailure(AccumulationDispatchError.InvalidContext) # Invalid memory is a local invariant refusal.
  hostSuccess[AccumulationDispatchError](response)

## The execution engine calls this private handler only for validated ecalli suspensions.
proc dispatch(context: var DispatchContext, stopped: StepOutcome): HostResult[
    AccumulationDispatchError] {.raises: [].} =
  let cpu = machineInfo(stopped.machine).value
  let memory = memoryOf(stopped.machine).value
  case uint64(stopped.hostCall)
  of 0:
    # GP general gas call reports the credit after its own charge.
    hostSuccess[AccumulationDispatchError](gasHostResponse(cpu.gas, cpu.registers, memory))
  of 2:
    # All fetch sources were captured from this invocation before execution began.
    let fetched = fetchContextResponse(context.fetch, cpu.gas, cpu.registers, memory,
      context.copyLimit)
    case fetched.error
    of FetchError.None:
      hostSuccess[AccumulationDispatchError](fetched.value) # Includes charged panic and gas exhaustion.
    of FetchError.LimitExceeded:
      hostFailure(AccumulationDispatchError.LimitExceeded) # Local copy policy is not guest failure.
    else:
      hostFailure(AccumulationDispatchError.InvalidContext) # Never fabricate protocol absence.
  of 18, 26:
    effectResponse(context, cpu, memory, uint64(stopped.hostCall) == 18) # Exact accumulation-only IDs.
  of 1, 3..6, 15..17, 19..25, 27:
    # These calls belong to accumulation's F but are not implemented by this adapter yet.
    hostFailure(AccumulationDispatchError.UnsupportedHostCall)
  else:
    # Refine-only IDs 7..14 and all other full-width IDs take accumulation's unknown branch.
    hostSuccess[AccumulationDispatchError](unknownHostResponse(cpu.gas, cpu.registers, memory))

## Execute only the supplied prepared machine, with entropy and inputs derived from its bootstrap.
## Capture limits apply before execution; copy and engine budgets remain independent local policies.
## Each call prepares I from this machine's own bootstrap and starts from its immutable initial CPU.
## No caller-supplied replacement effects, persistent writes or partial results escape.
proc executeAccumulationMachine*(prepared: PreparedAccumulationMachine, parameters: Parameters,
    fetchLimits: FetchAccumulationLimits, copyLimit: MemoryByteLimit,
    steps: ExecutionStepLimit, calls: HostCallLimit,
    cycles: GasCycleLimit, contextConfig: AccumulationContextConfig): AccumulationDispatchResult =
  let captured = machineFetchContext(prepared, parameters, fetchLimits)
  case captured.error
  of InvocationFetchError.None:
    discard # Successful capture also proves the machine and invocation owners are initialized.
  of InvocationFetchError.InvalidMachine:
    # No default owner may authorize a synthetic invocation.
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidMachine)
  of InvocationFetchError.InvalidParameters:
    # Configuration must be valid before any guest instruction runs.
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidParameters)
  of InvocationFetchError.LimitExceeded:
    # Pre-execution capture policy remains a local refusal.
    return AccumulationDispatchResult(status: AccumulationDispatchError.LimitExceeded)
  else:
    # Failed input encoding or context construction exposes no partial environment.
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidContext)
  let initial = prepareAccumulationContexts(prepared.machineBootstrap.value, contextConfig)
  if initial.error == AccumulationContextError.LimitExceeded:
    return AccumulationDispatchResult(status: AccumulationDispatchError.LimitExceeded) # Bound chapter copies.
  if initial.error != AccumulationContextError.None:
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidContext) # Require exact initial I.
  let initialized = prepareAccumulationEffects(initial.value)
  if initialized.error != AccumulationEffectError.None:
    return AccumulationDispatchResult(status: AccumulationDispatchError.InvalidContext) # No partial pair.
  var context = DispatchContext(fetch: captured.value, copyLimit: copyLimit,
      effects: initialized.value)
  let evaluated = executeWithHost(prepared.accumulationMachine.value, context, dispatch,
    steps, calls, cycles)
  case evaluated.error
  of HostExecutionError.None:
    # Preserve halt, panic, fault and gas outcomes without inventing a Psi_A transition.
    AccumulationDispatchResult(status: AccumulationDispatchError.None, completed: evaluated.value,
      completedEffects: context.effects)
  of HostExecutionError.ExecutionFailure:
    # Keep exact engine refusal, including separate step, host-call and gas-analysis budgets.
    AccumulationDispatchResult(status: AccumulationDispatchError.ExecutionFailure,
      reason: evaluated.executionError)
  of HostExecutionError.HostFailure:
    AccumulationDispatchResult(status: evaluated.hostError) # Failed callbacks publish no successor.
  else:
    AccumulationDispatchResult(status: AccumulationDispatchError.InvalidContext) # No default success.
