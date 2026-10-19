# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Merge supported common-source execution credits and terminal-selected provisions on a private complete-map fork.
## Supports explicit executed subsets or complete input coverage with certified skips; no round/block certificate is claimed.

import std/algorithm
import ../codec/[bounded, composite, header, state_accounts, state_trie]
import ./[accumulation_inputs, accumulation_service, accumulation_invocation, accumulation_context,
  accumulation_effects, accumulation_dispatch, accumulation_outcome, accumulation_provisions,
  accumulation_skip,
  accumulation_terminal_provisions, store]

type
  AccumulationBatchLimits* = object ## Account merge work is independently bounded from union traversal/copy/wire work.
    accounts*: ElementLimit ## Maximum changed self-metadata records encoded for incoming credits.
    provisions*: AccumulationProvisionUnionLimits ## Independent terminal union traversal, copy and wire ceilings.
  AccumulationBatchError* {.pure.} = enum ## Refusals expose only their reasons; no earlier credit, candidate root or partial terminal set escapes.
    Uninitialized,      ## Default result or plan without initialized ownership.
    None,               ## Complete selected success; guarded value extraction is available.
    InvalidInputs,      ## The expected prepared input owner is uninitialized.
    InvalidState,       ## The expected prior snapshot or publication store is uninitialized.
    InvalidExecution,   ## A local dispatch refusal supplied no completed execution source.
    SourceMismatch,     ## An execution or skip belongs to a different input owner or prior snapshot.
    InvalidSkip,        ## A default skip supplies no certified non-executing service.
    IncompleteCoverage, ## Executions and skips do not cover the expected input service count.
    InvalidSlot,        ## A certified skip belongs to a different candidate slot.
    DuplicateService,   ## A service occurs more than once across executions and skips.
    InvalidIndex,       ## The plan-owned execution ordinal is outside the retained outcomes.
    StaleState,         ## The publication store no longer retains this plan's exact prior version.
    UnsupportedAccountEffects, ## Selected account changes need a merger beyond incoming-credit metadata.
    LimitExceeded,      ## Batch descriptors or account writes exceed local preparation ceilings.
    TerminalFailure,    ## Terminal preparation or provision fulfillment refused; inspect its nested reason.
    StoreFailure        ## The private account-write phase refused; inspect storeError.
  AccumulationBatchInfo* = object ## Copied observations distinguish complete input coverage from an explicit subset; neither certifies a round.
    executions*: int      ## Unique services with genuine completed executions.
    skipped*: int         ## Unique services with certified non-executing outcomes.
    completeInputs*: bool ## Every service in the retained input owner is represented exactly once.
    accountWrites*: int   ## Changed self-metadata records prepared for incoming credits.
    terminal*: AccumulationTerminalProvisionInfo ## Checked invocation slot and selected-provision accounting.
  # Acyclic owner retains exact input/prior provenance, private metadata writes and normalized terminal effects.
  BatchData = ref object
    inputs: PreparedAccumulationInputs
    prior: StateStoreSnapshot
    writes: seq[StateWrite]
    terminal: PreparedTerminalAccumulationProvisions
    skipped: int
    completeInputs: bool
  PreparedAccumulationBatch* = object ## Only verified common-source, unique-service outcomes produce a batch plan.
    data: nil BatchData
  AccumulationBatchResult*[T] = object ## Nested failure alternatives retain enums alone, with guarded extraction of the selected reason.
    case status: AccumulationBatchError
    of None:
      completed: T # Only successful preparation/query/application exposes an immutable owner or copied facts.
    of TerminalFailure:
      terminalReason: AccumulationTerminalProvisionError
      normalizationReason: AccumulationOutcomeError
      provisionReason: AccumulationProvisionError
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Every other refusal/default carries just its outer reason.

func error*[T](outcome: AccumulationBatchResult[T]): AccumulationBatchError =
  ## Inspect the selected alternative without permitting retagging.
  outcome.status
func value*[T](outcome: AccumulationBatchResult[T]): T {.inline,
    requires: outcome.status == AccumulationBatchError.None.} =
  ## Extract complete selected success under checked optimized contracts.
  outcome.completed
func terminalError*[T](outcome: AccumulationBatchResult[
    T]): AccumulationTerminalProvisionError {.inline,

requires: outcome.status == AccumulationBatchError.TerminalFailure.} =
  ## Inspect only an actual terminal adapter refusal.
  outcome.terminalReason
func normalizationError*[T](outcome: AccumulationBatchResult[T]): AccumulationOutcomeError {.inline,
    requires: outcome.status == AccumulationBatchError.TerminalFailure and
      outcome.terminalReason == AccumulationTerminalProvisionError.NormalizationFailure.} =
  ## Inspect only the nested normalization alternative, preserving its specification gate.
  outcome.normalizationReason
func provisionError*[T](outcome: AccumulationBatchResult[T]): AccumulationProvisionError {.inline,
    requires: outcome.status == AccumulationBatchError.TerminalFailure and
      outcome.terminalReason == AccumulationTerminalProvisionError.ProvisionFailure.} =
  ## Inspect only the nested union/fulfillment alternative.
  outcome.provisionReason
func storeError*[T](outcome: AccumulationBatchResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationBatchError.StoreFailure.} =
  ## Inspect only a refused private account-write phase.
  outcome.storeReason

# Translate reason-only terminal failure without retaining a parent success payload or candidate state.
func terminalRefusal[T, U](failed: AccumulationTerminalProvisionResult[U]): AccumulationBatchResult[T] =
  var normalized = AccumulationOutcomeError.Uninitialized
  var provided = AccumulationProvisionError.Uninitialized
  if failed.error == AccumulationTerminalProvisionError.NormalizationFailure:
    normalized = failed.normalizationError # Only the selected nested reason is read.
  if failed.error == AccumulationTerminalProvisionError.ProvisionFailure:
    provided = failed.provisionError # Every other nested reason remains inaccessible to callers.
  AccumulationBatchResult[T](status: AccumulationBatchError.TerminalFailure,
    terminalReason: failed.error, normalizationReason: normalized, provisionReason: provided)

# Sort numeric service IDs independently of execution order or little-endian key bytes.
func compareService(left, right: ServiceIndex): int =
  if uint32(left) < uint32(right): return -1 # Prove uniqueness before any union hashing.
  if uint32(left) > uint32(right): return 1
  0

proc batchInfo*(plan: PreparedAccumulationBatch): AccumulationBatchResult[AccumulationBatchInfo] =
  ## Copy observations without granting mutable metadata, arrays or replaceable publication provenance.
  let data = plan.data
  if data == nil:
    return AccumulationBatchResult[AccumulationBatchInfo](
        status: AccumulationBatchError.Uninitialized) # Defaults are not empty batches.
  AccumulationBatchResult[AccumulationBatchInfo](status: AccumulationBatchError.None,
    completed: AccumulationBatchInfo(executions: data.terminal.terminalProvisionInfo.value.provisions.contexts,
      skipped: data.skipped, completeInputs: data.completeInputs,
      accountWrites: data.writes.len, terminal: data.terminal.terminalProvisionInfo.value))

proc batchOutcomeAt*(plan: PreparedAccumulationBatch, index: AccumulationProvisionSourceIndex):
    AccumulationBatchResult[AccumulationOutcome] =
  ## Retain one genuine normalized outcome in the original execution order.
  let data = plan.data
  if data == nil:
    return AccumulationBatchResult[AccumulationOutcome](
        status: AccumulationBatchError.Uninitialized) # No fabricated terminal source.
  let retained = data.terminal.terminalProvisionOutcomeAt(index)
  if retained.error == AccumulationTerminalProvisionError.InvalidIndex:
    return AccumulationBatchResult[AccumulationOutcome](
        status: AccumulationBatchError.InvalidIndex) # Parent proves the full-width ordinal.
  AccumulationBatchResult[AccumulationOutcome](status: AccumulationBatchError.None,
      completed: retained.value)

# Shared preparation proves source ownership before retaining credits or normalizing genuine executions.
proc prepareBatch(inputs: PreparedAccumulationInputs, prior: StateStoreSnapshot,
    executions: openArray[AccumulationDispatchResult], skipped: openArray[SkippedAccumulation],
    slot: HeaderSlot, limits: AccumulationBatchLimits, requireComplete: bool):
    AccumulationBatchResult[PreparedAccumulationBatch] =
  # Refuse without exposing partially retained service rows or encoded account writes.
  template fail(reason: AccumulationBatchError) =
    return AccumulationBatchResult[PreparedAccumulationBatch](status: reason)
  let count = inputs.invocationServiceCount
  if count.error != AccumulationInputError.None:
    fail(AccumulationBatchError.InvalidInputs) # A default input owner is not an initialized empty set.
  if not sameStateSnapshot(prior, prior):
    fail(AccumulationBatchError.InvalidState) # Defaults cannot authorize a complete-map candidate.
  # The prepared owner bounds coverage; subtraction proves the combined descriptor extent before addition.
  if requireComplete and (executions.len > count.value or skipped.len != count.value -
      executions.len):
    fail(AccumulationBatchError.IncompleteCoverage)
  if skipped.len > high(int) - executions.len:
    fail(AccumulationBatchError.LimitExceeded)
  let serviceCount = executions.len + skipped.len
  if uint64(executions.len) > uint64(limits.provisions.contexts) or
      serviceCount > high(int) div (sizeof(PreparedAccumulationService)+sizeof(
          ServiceIndex)+sizeof(StateWrite)+ServiceMetadataBytes):
    fail(AccumulationBatchError.LimitExceeded) # Bound all descriptors and fixed account bytes before allocation.
  var services = newSeq[PreparedAccumulationService](serviceCount)
  var ids = newSeq[ServiceIndex](serviceCount)
  for index, execution in executions:
    # A local execution refusal exposes no source and can never be treated as guest panic/rollback.
    if execution.error != AccumulationDispatchError.None:
      fail(AccumulationBatchError.InvalidExecution)
    let source = execution.effects.effectsSource.value.initialContext(
        AccumulationDimension.Regular).value
    let service = source.contextInvocation.value.bootstrapService.value
    if not serviceSourceMatches(service, inputs, prior):
      fail(AccumulationBatchError.SourceMismatch) # Equal metadata, gas, roots or slot do not replace actual owner provenance.
    services[index] = service
    ids[index] = service.serviceInfo.value.service
  for index, outcome in skipped:
    # Only the real code-resolution gate supplies a service; defaults cannot impersonate zero-gas outcomes.
    let source = outcome.skipService
    if source.error != AccumulationSkipError.None:
      fail(AccumulationBatchError.InvalidSkip)
    let service = source.value
    if not serviceSourceMatches(service, inputs, prior):
      fail(AccumulationBatchError.SourceMismatch)
    let info = service.serviceInfo.value
    if uint32(info.slot) != uint32(slot):
      fail(AccumulationBatchError.InvalidSlot)
    services[executions.len + index] = service
    ids[executions.len + index] = info.service
  ids.sort(compareService)
  for index in 1..<ids.len:
    if uint32(ids[index-1]) == uint32(ids[index]):
      fail(AccumulationBatchError.DuplicateService) # An execution or skip may represent each service only once.
  var writes: seq[StateWrite] = @[]
  for service in services:
    # Current preparation changes this private branch only when incoming credit changed self metadata.
    if not sameStateSnapshot(service.serviceState.value, prior):
      if uint64(writes.len) >= uint64(limits.accounts):
        fail(AccumulationBatchError.LimitExceeded) # Check fixed metadata work before encoding/copying it.
      let info = service.serviceInfo.value
      let entry = serviceMetadataEntry(info.service, info.account, ByteLimit(
          ServiceMetadataBytes)).value
      writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value))
  let selected = prepareTerminalAccumulationProvisions(executions, slot, limits.provisions)
  if selected.error != AccumulationTerminalProvisionError.None:
    return terminalRefusal[PreparedAccumulationBatch, PreparedTerminalAccumulationProvisions](selected)
  when declared(effectAccounts):
    # PVM storage-write integration exposes versioned accounts separately from immutable initial provenance.
    # This bounded merger must refuse a selected mutation instead of silently replacing it with initial credit.
    for index in 0..<executions.len:
      let service = services[index]
      let outcome = selected.value.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(
          uint64(index))).value
      let current = outcome.outcomeContext.value.effectAccounts
      if current.error != AccumulationEffectError.None:
        fail(AccumulationBatchError.UnsupportedAccountEffects) # No missing current-account owner can authorize a merge.
      if not sameStateSnapshot(current.value, service.serviceState.value):
        fail(AccumulationBatchError.UnsupportedAccountEffects) # Rolled-back regular writes do not affect the selected checkpoint.
  AccumulationBatchResult[PreparedAccumulationBatch](status: AccumulationBatchError.None,
    completed: PreparedAccumulationBatch(data: BatchData(inputs: inputs, prior: prior,
      writes: writes, terminal: selected.value, skipped: skipped.len,
      completeInputs: serviceCount == count.value)))

proc prepareAccumulationBatch*(inputs: PreparedAccumulationInputs, prior: StateStoreSnapshot,
    executions: openArray[AccumulationDispatchResult], slot: HeaderSlot,
    limits: AccumulationBatchLimits): AccumulationBatchResult[PreparedAccumulationBatch] =
  ## Prepare an explicit unique-service executed subset from one input owner and exact prior version.
  ## Inputs remain stable during this call; omissions receive no incoming credit from this subset.
  prepareBatch(inputs, prior, executions, [], slot, limits, false)

proc prepareCompleteAccumulationBatch*(inputs: PreparedAccumulationInputs,
    prior: StateStoreSnapshot, executions: openArray[AccumulationDispatchResult],
        skipped: openArray[SkippedAccumulation],
    slot: HeaderSlot, limits: AccumulationBatchLimits): AccumulationBatchResult[
        PreparedAccumulationBatch] =
  ## Require exactly one real execution or certified skip per prepared input service, from the exact prior and slot.
  ## Merge all incoming credits atomically with selected provisions; no admitted-round provenance is implied.
  ## Borrowed arrays remain stable during preparation; the plan retains only immutable owners and copied writes.
  prepareBatch(inputs, prior, executions, skipped, slot, limits, true)

proc applyAccumulationBatch*(state: var StateStore, plan: PreparedAccumulationBatch):
    AccumulationBatchResult[StateStoreSnapshot] =
  ## Apply credit merge then fnprovide privately; only complete success publishes the caller's store.
  ## Exact prior identity prevents lost updates and duplicate incoming credit; phase-local store limits are inherited.
  let data = plan.data
  if data == nil:
    return AccumulationBatchResult[StateStoreSnapshot](
        status: AccumulationBatchError.Uninitialized) # No default plan authorizes writes.
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return AccumulationBatchResult[StateStoreSnapshot](
        status: AccumulationBatchError.InvalidState) # No default state can satisfy source ownership.
  if not sameStateSnapshot(current.value, data.prior):
    return AccumulationBatchResult[StateStoreSnapshot](
        status: AccumulationBatchError.StaleState) # Reject before any hashing or private mutation.
  var working = forkStateStore(data.prior).value
  let credited = working.apply(data.writes)
  if credited.error != StateStoreError.None:
    return AccumulationBatchResult[StateStoreSnapshot](status: AccumulationBatchError.StoreFailure,
      storeReason: credited.error) # Neither a credit record nor candidate root reaches the caller.
  let provided = integrateTerminalAccumulationProvisions(working, data.terminal)
  if provided.error != AccumulationTerminalProvisionError.None:
    return terminalRefusal[StateStoreSnapshot, StateStoreSnapshot](
        provided) # Discard even a fully credited private candidate on late refusal.
  state = working
  AccumulationBatchResult[StateStoreSnapshot](status: AccumulationBatchError.None,
      completed: provided.value)
