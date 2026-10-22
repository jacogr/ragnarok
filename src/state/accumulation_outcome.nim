# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Collapse completed accumulation execution into one immutable implication context and capped gas use.
## Exposes normalizeAccumulationOutcome, retained context/info extraction and guarded typed refusals.
## See spec/pvm-hash-return-provisions.md for the scoped adoption of GP #533's regular projection.

import ../codec/[work_digest, composite, state_outputs]
import ../pvm/[machine, step, output]
import ./[accumulation_dispatch, accumulation_context, accumulation_effects,
  accumulation_invocation, accumulation_service]

type
  AccumulationTermination* {.pure.} = enum ## Normalized protocol termination; a physical fault follows Psi_M's panic branch.
    Halt, Panic, OutOfGas
  AccumulationOutcomeError* {.pure.} = enum ## Local refusals contain no selected state, gas usage or output commitment.
    Uninitialized, None, InvalidExecution, InvalidContext,
    AmbiguousProvisions ## Reserved historical refusal; the adopted #533 projection no longer emits it.
  AccumulationOutcomeInfo* = object ## Copied final metadata is inseparable from its selected immutable implication context.
    service*: ServiceIndex
    termination*: AccumulationTermination
    dimension*: AccumulationDimension
    gasUsed*: Gas
    hasYield*: bool
    transfers*, provisions*: int
  ## Private acyclic owner retains the final context and copied metadata, never the caller's result storage.
  OutcomeData = ref object
    context: AccumulationEffectContext
    info: AccumulationOutcomeInfo
  AccumulationOutcome* = object ## Read-only completed outcome; a default handle is not a successful empty accumulation.
    data: nil OutcomeData
  AccumulationOutcomeResult*[T] = object ## Only selected success carries a handle, context or metadata; default/refused alternatives carry a reason.
    case status: AccumulationOutcomeError
    of None:
      completed: T # Extract only after selecting successful normalization or retained-owner access.
    else:
      discard      # No partial outcome accompanies a refusal.

func error*[T](outcome: AccumulationOutcomeResult[T]): AccumulationOutcomeError =
  ## Inspect status without granting mutation or result retagging.
  outcome.status
func value*[T](outcome: AccumulationOutcomeResult[T]): T {.inline,
    requires: outcome.status == AccumulationOutcomeError.None.} =
  ## Retain complete selected success under checked optimized result contracts.
  outcome.completed

proc outcomeContext*(outcome: AccumulationOutcome): AccumulationOutcomeResult[
    AccumulationEffectContext] =
  ## Retain final selected effects, including any 32-byte halt-return override already applied to the yield.
  if outcome.data == nil:
    return AccumulationOutcomeResult[AccumulationEffectContext](status:
      AccumulationOutcomeError.Uninitialized) # No fabricated initial or posterior context.
  AccumulationOutcomeResult[AccumulationEffectContext](status: AccumulationOutcomeError.None,
    completed: outcome.data.context)

proc outcomeInfo*(outcome: AccumulationOutcome): AccumulationOutcomeResult[
    AccumulationOutcomeInfo] =
  ## Copy protocol metadata; immutable context extraction carries all state/input/chapter ownership.
  if outcome.data == nil:
    return AccumulationOutcomeResult[AccumulationOutcomeInfo](status:
      AccumulationOutcomeError.Uninitialized) # No fabricated zero gas usage.
  AccumulationOutcomeResult[AccumulationOutcomeInfo](status: AccumulationOutcomeError.None,
    completed: outcome.data.info)

proc normalizeAccumulationOutcome*(execution: AccumulationDispatchResult):
    AccumulationOutcomeResult[AccumulationOutcome] =
  ## Normalize only a complete adapter result; callers cannot supply substitute CPU/effect/source triples.
  ## Reads at most 32 guest bytes, retains immutable owners and never hashes or writes persistent state.
  ## Refuse atomically, releasing any locally retained candidate contexts.
  template fail(reason: AccumulationOutcomeError) =
    return AccumulationOutcomeResult[AccumulationOutcome](status: reason)
  if execution.error != AccumulationDispatchError.None:
    fail(AccumulationOutcomeError.InvalidExecution) # Local engine/host refusals never become guest panic.
  let stopped = execution.value
  var dimension = AccumulationDimension.Exceptional
  var termination = AccumulationTermination.Panic
  case stopped.exit
  of StepExit.Halt:
    dimension = AccumulationDimension.Regular # Normal halt commits current supported implications.
    termination = AccumulationTermination.Halt
  of StepExit.OutOfGas:
    termination = AccumulationTermination.OutOfGas # Unpaid blocks and exhausted host gas both select the exceptional context.
  of StepExit.Panic, StepExit.Fault:
    discard # Psi_M maps all other completed terminal exits to panic before C selects Y.
  else:
    fail(AccumulationOutcomeError.InvalidExecution) # Suspensions and unfinished execution are not Psi_M outputs.
  let effects = execution.effects
  let source = effects.effectsSource
  if source.error != AccumulationEffectError.None:
    fail(AccumulationOutcomeError.InvalidContext) # No replacement initialization certificate is accepted.
  let initial = source.value.initialContext(AccumulationDimension.Regular)
  if initial.error != AccumulationContextError.None:
    fail(AccumulationOutcomeError.InvalidContext) # Preserve the original bootstrap identity.
  let bootstrap = initial.value.contextInvocation.value
  let credit = uint64(bootstrap.bootstrapService.value.serviceInfo.value.gas)
  let cpu = machineInfo(stopped.machine).value
  if uint64(cpu.gas) > credit:
    fail(AccumulationOutcomeError.InvalidExecution) # Prove subtraction before computing capped consumption.
  var selected = effects.effectContext(dimension).value
  if termination == AccumulationTermination.Halt and uint64(cpu.registers[8]) == 32:
    # Every other length normalizes identically whether readable or not; do not allocate that return blob.
    let returned = captureOutput(stopped, OutputByteLimit(32))
    if returned.error != OutputError.None:
      fail(AccumulationOutcomeError.InvalidExecution) # A private completed execution must have a valid CPU.
    if returned.value.len == 32:
      # Adopted #533 C selects all regular X effects, including provisions; only its yield is overridden.
      var bytes = default(array[32, byte])
      for i in 0..<32:
        bytes[i] = returned.value[i] # Copy a present hash, including the all-zero hash.
      let overridden = recordAccumulationYield(effects, OutputCommitment(bytes))
      if overridden.error != AccumulationEffectError.None:
        fail(AccumulationOutcomeError.InvalidContext) # No partially overridden context escapes.
      selected = overridden.value.effectContext(AccumulationDimension.Regular).value
  let info = selected.effectInfo.value
  let data = OutcomeData(context: selected, info: AccumulationOutcomeInfo(service: info.service,
    termination: termination, dimension: dimension, gasUsed: Gas(credit-uint64(cpu.gas)),
    hasYield: info.hasYield, transfers: info.transfers, provisions: info.provisions))
  AccumulationOutcomeResult[AccumulationOutcome](status: AccumulationOutcomeError.None,
    completed: AccumulationOutcome(data: data))
