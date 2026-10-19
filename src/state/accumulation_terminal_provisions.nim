# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind provision union/fulfillment to actual terminal-selected execution effects and their invocation slot.
## Explicit posterior complete maps remain caller-owned; this is not a merged-round or block certificate.

import ../codec/header
import ./[accumulation_dispatch, accumulation_outcome, accumulation_provisions,
  accumulation_context, accumulation_effects, accumulation_invocation, accumulation_service, store]

type
  ## Local preparation failures retain no partial selected outcome, union or published map.
  AccumulationTerminalProvisionError* {.pure.} = enum
    Uninitialized, None, InvalidSlot, InvalidIndex, LimitExceeded, NormalizationFailure, ProvisionFailure
  ## Copied observations preserve the checked invocation slot and existing union accounting.
  AccumulationTerminalProvisionInfo* = object
    slot*: HeaderSlot
    provisions*: AccumulationProvisionPlanInfo
  ## Private acyclic owner retains selected outcomes and their independently prepared provision union.
  TerminalProvisionData = ref object
    outcomes: seq[AccumulationOutcome]
    plan: PreparedAccumulationProvisions
    slot: HeaderSlot
  ## Only normalization of completed dispatch results can construct this stronger plan.
  PreparedTerminalAccumulationProvisions* = object
    data: nil TerminalProvisionData
  ## Reason-only failures keep normalization gates separate from union/application refusals.
  AccumulationTerminalProvisionResult*[T] = object
    case status: AccumulationTerminalProvisionError
    of None:
      completed: T # Success extraction is guarded even in optimized native builds.
    of NormalizationFailure:
      normalizationReason: AccumulationOutcomeError
    of ProvisionFailure:
      provisionReason: AccumulationProvisionError
    else:
      discard      # Defaults, slot/index and early extent refusals carry no success storage.

## Inspect only the selected reason; no mutable discriminator escapes.
func error*[T](outcome: AccumulationTerminalProvisionResult[
    T]): AccumulationTerminalProvisionError = outcome.status
## Extract only the successful alternative.
func value*[T](outcome: AccumulationTerminalProvisionResult[T]): T {.inline,
    requires: outcome.status == AccumulationTerminalProvisionError.None.} = outcome.completed
## Preserve the exact terminal normalization refusal, including its parked specification gate.
func normalizationError*[T](outcome: AccumulationTerminalProvisionResult[
    T]): AccumulationOutcomeError {.inline,

requires: outcome.status == AccumulationTerminalProvisionError.NormalizationFailure.} = outcome.normalizationReason
## Preserve the exact union or atomic application refusal without fabricating terminal failure.
func provisionError*[T](outcome: AccumulationTerminalProvisionResult[
    T]): AccumulationProvisionError {.inline,

requires: outcome.status == AccumulationTerminalProvisionError.ProvisionFailure.} = outcome.provisionReason

## Copy fixed observations without exposing retained outcome arrays or a replaceable slot.
proc terminalProvisionInfo*(plan: PreparedTerminalAccumulationProvisions):
    AccumulationTerminalProvisionResult[AccumulationTerminalProvisionInfo] =
  let data = plan.data
  if data == nil:
    return AccumulationTerminalProvisionResult[AccumulationTerminalProvisionInfo](status:
      AccumulationTerminalProvisionError.Uninitialized) # A default is not an initialized empty batch.
  AccumulationTerminalProvisionResult[AccumulationTerminalProvisionInfo](status:
    AccumulationTerminalProvisionError.None, completed: AccumulationTerminalProvisionInfo(
      slot: data.slot, provisions: data.plan.provisionPlanInfo.value))

## Retain the exact normalized outcome corresponding to this bounded input ordinal.
proc terminalProvisionOutcomeAt*(plan: PreparedTerminalAccumulationProvisions,
    index: AccumulationProvisionSourceIndex): AccumulationTerminalProvisionResult[
        AccumulationOutcome] =
  let data = plan.data
  if data == nil:
    return AccumulationTerminalProvisionResult[AccumulationOutcome](status:
      AccumulationTerminalProvisionError.Uninitialized) # Defaults grant neither metadata nor selected contexts.
  if uint64(index) >= uint64(data.outcomes.len):
    return AccumulationTerminalProvisionResult[AccumulationOutcome](status:
      AccumulationTerminalProvisionError.InvalidIndex) # Prove the full ordinal before narrowing to native int.
  AccumulationTerminalProvisionResult[AccumulationOutcome](status:
    AccumulationTerminalProvisionError.None, completed: data.outcomes[int(uint64(index))])

## Normalize every completed execution before union hashing; the caller borrows the input stably during this call.
## Repeated executions consume repeated traversal budgets; no round membership or shared parent is certified.
proc prepareTerminalAccumulationProvisions*(executions: openArray[AccumulationDispatchResult],
    slot: HeaderSlot, limits: AccumulationProvisionUnionLimits):
    AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions] =
  if uint64(executions.len) > uint64(limits.contexts) or
      executions.len > high(int) div (sizeof(AccumulationOutcome)+sizeof(
          AccumulationEffectContext)):
    return AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions](status:
      AccumulationTerminalProvisionError.LimitExceeded) # Bound all retained-handle descriptors before allocation.
  var outcomes = newSeq[AccumulationOutcome](executions.len)
  var contexts = newSeq[AccumulationEffectContext](executions.len)
  for index, execution in executions:
    # The normalizer alone selects regular/exceptional state, output override and capped gas metadata.
    let normalized = normalizeAccumulationOutcome(execution)
    if normalized.error != AccumulationOutcomeError.None:
      return AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions](status:
        AccumulationTerminalProvisionError.NormalizationFailure,
        normalizationReason: normalized.error) # No earlier candidate or provision hash escapes late refusal.
    let context = normalized.value.outcomeContext.value
    let invocation = context.effectInitialContext.value.contextInvocation.value
    let invoked = invocation.bootstrapService.value.serviceInfo.value
    if uint32(invoked.slot) != uint32(slot):
      return AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions](status:
        AccumulationTerminalProvisionError.InvalidSlot) # Bind timestamps to actual invocation preparation, never an arbitrary replacement.
    outcomes[index] = normalized.value
    contexts[index] = context # Retain only the normalized context, never the unselected regular alternative.
  let prepared = prepareAccumulationProvisions(contexts, limits)
  if prepared.error != AccumulationProvisionError.None:
    return AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions](status:
      AccumulationTerminalProvisionError.ProvisionFailure,
      provisionReason: prepared.error) # Release all temporary owners without a partially prepared union.
  AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions](status:
    AccumulationTerminalProvisionError.None, completed: PreparedTerminalAccumulationProvisions(
      data: TerminalProvisionData(outcomes: outcomes, plan: prepared.value, slot: slot)))

## Atomically fulfill requests in the explicit posterior complete map using only this plan's checked slot.
## Cached identities, cancellation filtering and write/root rollback retain the existing fnprovide contracts.
proc integrateTerminalAccumulationProvisions*(state: var StateStore,
    plan: PreparedTerminalAccumulationProvisions): AccumulationTerminalProvisionResult[
        StateStoreSnapshot] =
  let data = plan.data
  if data == nil:
    return AccumulationTerminalProvisionResult[StateStoreSnapshot](status:
      AccumulationTerminalProvisionError.Uninitialized) # Default plans never authorize publication.
  let applied = integrateAccumulationProvisions(state, data.plan, data.slot)
  if applied.error != AccumulationProvisionError.None:
    return AccumulationTerminalProvisionResult[StateStoreSnapshot](status:
      AccumulationTerminalProvisionError.ProvisionFailure,
      provisionReason: applied.error) # Preserve the original store and exact atomic refusal reason.
  AccumulationTerminalProvisionResult[StateStoreSnapshot](status:
    AccumulationTerminalProvisionError.None, completed: applied.value)
