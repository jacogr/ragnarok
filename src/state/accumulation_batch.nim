# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Merge common-source credits, selected self changes, created accounts and provisions on a private complete-map fork.
## Supports explicit executed subsets or complete input coverage with certified skips; no round/block certificate is claimed.

import std/algorithm
import ../codec/[bounded, composite, header, state_accounts, state_layout, state_trie]
import ./[accumulation_inputs, accumulation_service, accumulation_invocation, accumulation_context,
  accumulation_effects, accumulation_dispatch, accumulation_outcome, accumulation_provisions,
  accumulation_skip,
  accumulation_terminal_provisions, store]

type
  AccumulationBatchLimits* = object ## Account merge work is independently bounded from union traversal/copy/wire work.
    accounts*: ElementLimit ## Maximum invoking metadata records copied for credits or supported selected changes.
    createdAccounts*: ElementLimit ## Maximum genuine children copied as fixed metadata plus empty request; zero preserves the gate.
    selfWrites*: ElementLimit ## Maximum unique nonmetadata self keys copied across all selected executions; zero preserves the gate.
    selfValueBytes*: ByteLimit ## Aggregate copied final self values; deletions consume a key but no value bytes.
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
    UnsupportedAccountEffects, ## Selected changes exceed proven self/creation scope or conflict on physical keys.
    LimitExceeded,      ## Batch descriptors or account writes exceed local preparation ceilings.
    TerminalFailure,    ## Terminal preparation or provision fulfillment refused; inspect its nested reason.
    StoreFailure        ## The private account-write phase refused; inspect storeError.
  AccumulationBatchInfo* = object ## Copied observations distinguish complete input coverage from an explicit subset; neither certifies a round.
    executions*: int      ## Unique services with genuine completed executions.
    skipped*: int         ## Unique services with certified non-executing outcomes.
    completeInputs*: bool ## Every service in the retained input owner is represented exactly once.
    accountWrites*: int   ## Invoking metadata records prepared for credits or supported selected changes.
    createdAccounts*: int ## New foreign accounts published with the selected creator debit.
    selfWrites*: int      ## Unique nonmetadata keys prepared from selected self-write provenance.
    selfValueBytes*: uint64 ## Copied final self values, excluding fixed metadata and terminal provisions.
    terminal*: AccumulationTerminalProvisionInfo ## Checked invocation slot and selected-provision accounting.
  # Acyclic owner retains exact input/prior provenance, private metadata writes and normalized terminal effects.
  BatchData = ref object
    inputs: PreparedAccumulationInputs
    prior: StateStoreSnapshot
    writes: seq[StateWrite]
    metadataWrites: int
    selfBytes: uint64
    selfWriteCount, createdCount: int
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

# Compare only fixed physical keys; caller execution order never chooses a conflicting winner.
func compareAccountKey(left, right: StateKey): int =
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for index in 0..<31:
    if a[index] < b[index]: return -1 # Full serialized keys, not only service or logical raw key, identify conflicts.
    if a[index] > b[index]: return 1
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
      accountWrites: data.metadataWrites, createdAccounts: data.createdCount,
      selfWrites: data.selfWriteCount,
      selfValueBytes: data.selfBytes, terminal: data.terminal.terminalProvisionInfo.value))

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
  var creditWrites = 0'u64
  for service in services:
    # Preserve the original pre-hash refusal for the minimum metadata work already proved by incoming credits.
    if not sameStateSnapshot(service.serviceState.value, prior):
      if creditWrites >= uint64(limits.accounts):
        fail(AccumulationBatchError.LimitExceeded) # No union hashing is authorized by an insufficient credit budget.
      inc creditWrites
  let selected = prepareTerminalAccumulationProvisions(executions, slot, limits.provisions)
  if selected.error != AccumulationTerminalProvisionError.None:
    return terminalRefusal[PreparedAccumulationBatch, PreparedTerminalAccumulationProvisions](selected)
  var writes: seq[StateWrite] = @[]
  var metadataWrites = 0
  var selfWrites = 0'u64
  var selfBytes = 0'u64
  var createdCount = 0'u64
  for index, service in services:
    # Skips retain their credited initial map; executions must use one terminal-selected scope/account owner.
    var accounts = service.serviceState.value
    if index < executions.len:
      let outcome = selected.value.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(
        uint64(index))).value
      let context = outcome.outcomeContext.value
      let scope = context.effectAccountScope
      if scope.error != AccumulationEffectError.None or
          scope.value == AccumulationAccountScope.Unsupported:
        fail(AccumulationBatchError.UnsupportedAccountEffects) # Restored equal bytes cannot erase unsupported mutation ancestry.
      accounts = context.effectAccounts.value
      let children = context.effectCreatedAccountCount.value
      if uint64(children) > uint64(limits.createdAccounts)-createdCount:
        fail(AccumulationBatchError.LimitExceeded) # Bound all fixed child records before any copied payloads.
      for ordinal in 0..<children:
        if writes.len > high(int) div sizeof(StateWrite)-2:
          fail(AccumulationBatchError.LimitExceeded) # Each child adds exactly two fully bounded descriptors.
        let child = context.effectCreatedAccountAt(AccumulationCreatedAccountIndex(uint64(
            ordinal))).value
        let key = chapterServiceKey(StateChapter(255), child.service)
        if prior.lookup(key).error != StateStoreError.MissingKey:
          fail(AccumulationBatchError.UnsupportedAccountEffects) # Only accounts absent from the common prior belong to the supported new-account set.
        let record = accounts.lookup(key)
        let request = accounts.lookup(child.requestKey)
        if record.error != StateStoreError.None or record.value.byteLength != ServiceMetadataBytes:
          fail(AccumulationBatchError.UnsupportedAccountEffects) # A created child must retain complete metadata.
        if request.error != StateStoreError.None or request.value.byteLength != 1:
          fail(AccumulationBatchError.UnsupportedAccountEffects) # A captured child request must remain present and empty.
        let bytes = request.value.bytes
        if bytes[0] != 0:
          fail(AccumulationBatchError.UnsupportedAccountEffects) # The captured code request remains genuinely empty until fnprovide.
        writes.add(StateWrite(key: key, kind: StateWriteKind.Put, value: record.value.bytes))
        writes.add(StateWrite(key: child.requestKey, kind: StateWriteKind.Put, value: bytes))
        inc createdCount
      let count = context.effectAccountWriteCount.value
      if uint64(count) > uint64(limits.selfWrites)-selfWrites:
        fail(AccumulationBatchError.LimitExceeded) # Bound the entire selected trace before value copying or descriptor growth.
      for ordinal in 0..<count:
        if writes.len >= high(int) div sizeof(StateWrite):
          fail(AccumulationBatchError.LimitExceeded) # Prove the combined native descriptor extent before append.
        let key = context.effectAccountWriteKeyAt(AccumulationAccountWriteIndex(uint64(
            ordinal))).value
        let found = accounts.lookup(key)
        if found.error == StateStoreError.MissingKey:
          writes.add(StateWrite(key: key, kind: StateWriteKind.Delete)) # A selected deletion remains explicit even if it restored prior bytes.
        elif found.error == StateStoreError.None:
          let size = uint64(found.value.byteLength)
          if size > uint64(limits.selfValueBytes)-selfBytes:
            fail(AccumulationBatchError.LimitExceeded) # Bound exact aggregate payload before copying it from its retained owner.
          writes.add(StateWrite(key: key, kind: StateWriteKind.Put, value: found.value.bytes))
          selfBytes += size
        else:
          fail(AccumulationBatchError.UnsupportedAccountEffects) # No invalid current account owner supplies a fabricated deletion.
        inc selfWrites
    if not sameStateSnapshot(accounts, prior):
      # Common-source uniqueness makes these self keys disjoint; never copy a sibling's complete local map.
      if uint64(metadataWrites) >= uint64(limits.accounts) or writes.len >= high(int) div sizeof(StateWrite):
        fail(AccumulationBatchError.LimitExceeded) # Bound the fixed record before copying its bytes.
      let key = chapterServiceKey(StateChapter(255), service.serviceInfo.value.service)
      let record = accounts.lookup(key)
      if record.error != StateStoreError.None or record.value.byteLength != ServiceMetadataBytes:
        fail(AccumulationBatchError.UnsupportedAccountEffects) # No missing/incomplete self record authorizes publication.
      writes.add(StateWrite(key: key, kind: StateWriteKind.Put, value: record.value.bytes))
      inc metadataWrites
  var keys = newSeq[StateKey](writes.len)
  for index, write in writes:
    keys[index] = write.key # Fixed-key scratch detects cross-service or namespace conflicts without copying payloads.
  keys.sort(compareAccountKey)
  for index in 1..<keys.len:
    if compareAccountKey(keys[index-1], keys[index]) == 0:
      fail(AccumulationBatchError.UnsupportedAccountEffects) # No implicit winner for colliding physical account writes.
  AccumulationBatchResult[PreparedAccumulationBatch](status: AccumulationBatchError.None,
    completed: PreparedAccumulationBatch(data: BatchData(inputs: inputs, prior: prior,
      writes: writes, metadataWrites: metadataWrites, selfBytes: selfBytes,
      selfWriteCount: int(selfWrites), createdCount: int(createdCount),
      terminal: selected.value, skipped: skipped.len,
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
  ## Merge incoming credits and supported selected accounts atomically with provisions; no admitted-round provenance is implied.
  ## Borrowed arrays remain stable during preparation; the plan retains only immutable owners and copied writes.
  prepareBatch(inputs, prior, executions, skipped, slot, limits, true)

proc applyAccumulationBatch*(state: var StateStore, plan: PreparedAccumulationBatch):
    AccumulationBatchResult[StateStoreSnapshot] =
  ## Apply selected self metadata/credits then fnprovide privately; only complete success publishes the caller's store.
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
