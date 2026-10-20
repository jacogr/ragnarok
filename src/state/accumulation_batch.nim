# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Merge common-source credits, supported selected account changes and provisions on a private complete-map fork.
## Supports explicit executed subsets or complete input coverage with certified skips; no round/block certificate is claimed.

import std/algorithm
import ../codec/[natural, bounded, composite, header, state_accounts, state_authorization,
    state_privileges, state_layout, state_trie]
import ./[accumulation_inputs, accumulation_service, accumulation_invocation, accumulation_context,
  accumulation_effects, accumulation_dispatch, accumulation_outcome, accumulation_provisions,
  accumulation_skip, accumulation_transfers,
  accumulation_terminal_provisions, store]

type
  AccumulationBatchLimits* = object ## Account merge work is independently bounded from union traversal/copy/wire work.
    accounts*: ElementLimit ## Maximum invoking metadata records copied for credits or supported selected changes.
    deletedAccounts*: ElementLimit ## Maximum captured ejection facts inspected; participating targets remain gated.
    createdAccounts*: ElementLimit ## Maximum captured creation facts inspected, including prior-ID recreations.
    selfWrites*: ElementLimit ## Maximum unique nonmetadata self keys copied across all selected executions; zero preserves the gate.
    selfValueBytes*: ByteLimit ## Aggregate copied final self values; deletions consume a key but no value bytes.
    assignCores*: ElementLimit ## Complete positional core work when selected assign/bless exists; zero preserves the gate.
    assignBytes*: ByteLimit ## Aggregate C(2) plus the larger original/output C(12) byte ceiling.
    managerEntries*: ElementLimit ## Larger original/selected manager allowance dictionary; zero permits only empty dictionaries.
    managerBytes*: ByteLimit ## Aggregate original and selected manager C(12) bytes; zero preserves bless publication gate.
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
    UnsupportedAccountEffects, ## Selected changes exceed proven account scope or conflict on physical keys.
    LimitExceeded,      ## Batch descriptors or account writes exceed local preparation ceilings.
    TerminalFailure,    ## Terminal preparation or provision fulfillment refused; inspect its nested reason.
    StoreFailure        ## The private account-write phase refused; inspect storeError.
  AccumulationBatchInfo* = object ## Copied observations distinguish complete input coverage from an explicit subset; neither certifies a round.
    executions*: int      ## Unique services with genuine completed executions.
    skipped*: int         ## Unique services with certified non-executing outcomes.
    completeInputs*: bool ## Every service in the retained input owner is represented exactly once.
    assignmentWrites*: int ## Two canonical global chapter writes when selected assign/bless requires publication.
    accountWrites*: int   ## Invoking metadata records prepared for credits or supported selected changes.
    deletedAccounts*: int ## Prior accounts absent from selected final domains and actually removed.
    createdAccounts*: int ## Prior-absent foreign accounts actually published with the selected creator debit.
    selfWrites*: int      ## Unique nonmetadata keys prepared from selected self-write provenance.
    selfValueBytes*: uint64 ## Copied final self values, excluding fixed metadata and terminal provisions.
    terminal*: AccumulationTerminalProvisionInfo ## Checked invocation slot and selected-provision accounting.
  BatchTransferRow = object ## Private sort row keeps numeric service identity with its exact normalized outcome.
    service: ServiceIndex
    outcome: AccumulationOutcome
  # Acyclic owner retains exact input/prior provenance, private metadata writes and normalized terminal effects.
  BatchData = ref object
    inputs: PreparedAccumulationInputs
    prior: StateStoreSnapshot
    writes: seq[StateWrite]
    metadataWrites: int
    assignmentWrites: int
    selfBytes: uint64
    selfWriteCount, createdCount, deletedCount: int
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
      assignmentWrites: data.assignmentWrites, accountWrites: data.metadataWrites,
      deletedAccounts: data.deletedCount,
      createdAccounts: data.createdCount,
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

# Numeric service order is independent of execution order or serialized key bytes.
func compareTransferRow(left, right: BatchTransferRow): int =
  if uint32(left.service) < uint32(right.service): return -1 # Emit the entire smaller service's selected sequence first.
  if uint32(left.service) > uint32(right.service): return 1
  0

proc prepareBatchAccumulationTransfers*(plan: PreparedAccumulationBatch,
    limits: AccumulationTransferCollectionLimits): AccumulationBatchResult[
        PreparedAccumulationTransfers] =
  ## Collect this verified common-source batch's selected outcomes in numeric service order.
  ## This does not certify admitted-round coverage or paid gas; those remain with actual completion owners.
  let data = plan.data
  if data == nil:
    return AccumulationBatchResult[PreparedAccumulationTransfers](status:
      AccumulationBatchError.Uninitialized) # A default batch is not an initialized empty collection.
  let count = data.terminal.terminalProvisionInfo.value.provisions.contexts
  if uint64(count) > uint64(limits.sources) or
      count > high(int) div (sizeof(BatchTransferRow)+sizeof(AccumulationOutcome)):
    return AccumulationBatchResult[PreparedAccumulationTransfers](status:
      AccumulationBatchError.LimitExceeded) # Bound sort descriptors and captured immutable handles before allocation.
  var rows = newSeq[BatchTransferRow](count)
  for index in 0..<count:
    let outcome = data.terminal.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
    rows[index] = BatchTransferRow(service: outcome.outcomeInfo.value.service,
        outcome: outcome) # Batch preparation already proves unique source identity.
  rows.sort(compareTransferRow)
  var outcomes = newSeq[AccumulationOutcome](count)
  for index, row in rows:
    outcomes[index] = row.outcome # Preserve each selected append sequence while canonicalizing only service order.
  let collected = prepareAccumulationTransfers(outcomes, limits)
  if collected.error == AccumulationTransferCollectionError.LimitExceeded:
    return AccumulationBatchResult[PreparedAccumulationTransfers](status:
      AccumulationBatchError.LimitExceeded) # Duplicates still consume full item/memo capture budgets.
  if collected.error != AccumulationTransferCollectionError.None:
    return AccumulationBatchResult[PreparedAccumulationTransfers](status:
      AccumulationBatchError.InvalidExecution) # Private normalized batch outcomes cannot legitimately be invalid.
  AccumulationBatchResult[PreparedAccumulationTransfers](status:
    AccumulationBatchError.None, completed: collected.value)

# Inspect bounded immutable creation facts only after the caller has checked aggregate trace ceilings.
proc hasCreatedAccount(context: AccumulationEffectContext, service: ServiceIndex): bool =
  for ordinal in 0..<context.effectCreatedAccountCount.value:
    # Exact service identity proves that a retained prior ID was genuinely recreated.
    let child = context.effectCreatedAccountAt(AccumulationCreatedAccountIndex(uint64(
        ordinal))).value
    if uint32(child.service) == uint32(service): return true
  false

# An ignored prior-present creation must be paired with genuine selected ejection provenance.
proc hasDeletedAccount(context: AccumulationEffectContext, service: ServiceIndex): bool =
  for ordinal in 0..<context.effectDeletedAccountCount.value:
    # A matching successful eject explains how registrar creation obtained the occupied prior ID.
    let target = context.effectDeletedAccountAt(AccumulationDeletedAccountIndex(uint64(
        ordinal))).value
    if uint32(target.service) == uint32(service): return true
  false

# Look up privileges by original authority; skipped/absent services retain the initial roles.
proc selectedPrivileges(selected: PreparedTerminalAccumulationProvisions,
    service: ServiceIndex, initial: PrivilegeSnapshot): PrivilegeSnapshot =
  for index in 0..<selected.terminalProvisionInfo.value.provisions.contexts:
    let outcome = selected.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
    if uint32(outcome.outcomeInfo.value.service) == uint32(service):
      return outcome.outcomeContext.value.effectPrivileges.value # Terminal normalization already selected the exact checkpoint.
  initial

# GP accpar R preserves the original owner's handoff unless the original manager changed the role.
func selectedRole(original, manager, owner: ServiceIndex): ServiceIndex =
  if uint32(manager) == uint32(original): owner
  else: manager # A changed manager choice wins independently of execution order.

# Merge manager roles/allowances and original-assigner queues; validator staging remains gated.

proc assignmentWrites(selected: PreparedTerminalAccumulationProvisions,
    initial: InitialAccumulationContext, limits: AccumulationBatchLimits): AccumulationBatchResult[
        seq[StateWrite]] =
  template fail(reason: AccumulationBatchError) =
    ## Refuse without exposing a partial core prefix or any proposed global writes.
    return AccumulationBatchResult[seq[StateWrite]](status: reason)
  let count = selected.terminalProvisionInfo.value.provisions.contexts
  var assigned = false
  var blessed = false
  for index in 0..<count:
    let context = selected.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(uint64(
        index))).value.outcomeContext.value
    assigned = assigned or context.effectInfo.value.hasAssignments
    blessed = blessed or context.effectInfo.value.hasPrivileges
  if not assigned and not blessed:
    return AccumulationBatchResult[seq[StateWrite]](status: AccumulationBatchError.None,
        completed: @[]) # Preserve the no-assignment path without decoding/copying global chapters.
  let privileges = initial.contextPrivileges.value
  let queues = initial.contextQueues.value
  let info = privileges.privilegeInfo.value
  let manager = selectedPrivileges(selected, info.manager, privileges)
  let managerInfo = manager.privilegeInfo.value
  let cores = info.cores
  let allowances = managerInfo.always
  if uint64(cores) > uint64(limits.assignCores) or cores > high(int) div 2560 or
      cores > high(int) div sizeof(AuthorizerRow) or cores > high(int) div sizeof(ServiceIndex) or
      allowances > high(int) div sizeof(AlwaysAccumulate):
    fail(AccumulationBatchError.LimitExceeded) # Prove native row/hash/dictionary extents before allocation under wrapping arithmetic.
  let prior = initial.contextAccounts.value
  let rawQueues = prior.lookup(chapterKey(StateChapter(2)))
  let rawRoles = prior.lookup(chapterKey(StateChapter(12)))
  if rawQueues.error != StateStoreError.None or rawRoles.error != StateStoreError.None:
    fail(AccumulationBatchError.UnsupportedAccountEffects) # Initial context ownership must retain both exact complete components.
  let queueBytes = uint64(rawQueues.value.byteLength)
  let roleBytes = uint64(rawRoles.value.byteLength)
  # Canonical C(12) uses fixed role widths and a compact count; its size depends only on dictionary cardinality.
  let selectedCount = uint64(allowances)
  let countBytes = uint64(natural.encode(JamNatural(selectedCount)).len)
  if selectedCount > (high(uint64)-4*uint64(cores+3)-countBytes) div 12:
    fail(AccumulationBatchError.LimitExceeded) # Prove the full serialized extent before multiplication/addition.
  let outputRoleBytes = 4*uint64(cores+3)+countBytes+12*selectedCount
  if blessed and (uint64(max(info.always, allowances)) > uint64(limits.managerEntries) or
      roleBytes > uint64(limits.managerBytes) or outputRoleBytes > uint64(
          limits.managerBytes)-roleBytes):
    fail(AccumulationBatchError.LimitExceeded) # Both source/output dictionaries are bounded before copying entries.
  let retainedRoleBytes = max(roleBytes, outputRoleBytes)
  if queueBytes > uint64(limits.assignBytes) or retainedRoleBytes > uint64(
      limits.assignBytes)-queueBytes:
    fail(AccumulationBatchError.LimitExceeded) # Bound complete original/output global bytes, including manager dictionary growth.
  var rows = newSeq[AuthorizerRow](cores)
  let delegator = selectedPrivileges(selected, info.delegator, privileges).privilegeInfo.value
  let registrar = selectedPrivileges(selected, info.registrar, privileges).privilegeInfo.value
  var roles = PrivilegeState(manager: managerInfo.manager,
    delegator: selectedRole(info.delegator, managerInfo.delegator, delegator.delegator),
    registrar: selectedRole(info.registrar, managerInfo.registrar, registrar.registrar),
    assigners: newSeq[ServiceIndex](cores), always: newSeq[AlwaysAccumulate](allowances))
  for core in 0..<cores:
    let owner = privileges.privilegeAssignerAt(PrivilegeCoreIndex(uint64(core))).value
    var selectedQueues = queues
    var selectedRoles = privileges
    for index in 0..<count:
      let outcome = selected.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
      if uint32(outcome.outcomeInfo.value.service) == uint32(owner):
        let context = outcome.outcomeContext.value
        selectedQueues = context.effectQueues.value
        selectedRoles = context.effectPrivileges.value # Match original authority, never execution order or a new handoff destination.
    roles.assigners[core] = selectedRole(owner,
      manager.privilegeAssignerAt(PrivilegeCoreIndex(uint64(core))).value,
      selectedRoles.privilegeAssignerAt(PrivilegeCoreIndex(uint64(core))).value)
    rows[core] = newSeq[AuthorizerHash](80)
    for position in 0..<80:
      rows[core][position] = selectedQueues.authorizerAt(AuthorizationCoreIndex(uint64(core)),
          AuthorizationIndex(uint64(position))).value
  for index in 0..<allowances:
    roles.always[index] = manager.alwaysAccumulateAt(PrivilegeEntryIndex(uint64(
        index))).value # Retain the original manager's selected canonical dictionary, including empty/shrunk results.
  let config = AuthorizationConfig(cores: CoreCount(uint64(cores)), maxHashes: ElementLimit(uint64(
      cores)*80), maxBytes: ByteLimit(queueBytes))
  let encodedQueues = authorizationEntry(AuthorizationKind.Queues, rows, config)
  let encodedRoles = privilegeStateEntry(roles, PrivilegeConfig(cores: config.cores,
    maxAlways: ElementLimit(uint64(allowances)), maxBytes: ByteLimit(outputRoleBytes)))
  if encodedQueues.error != AuthorizationError.None or encodedRoles.error != PrivilegeError.None:
    fail(AccumulationBatchError.UnsupportedAccountEffects) # Global shapes and exact canonical size remain independently codec-checked.
  AccumulationBatchResult[seq[StateWrite]](status: AccumulationBatchError.None,
    completed: @[StateWrite(key: encodedQueues.value.key, kind: StateWriteKind.Put,
        value: encodedQueues.value.value),
      StateWrite(key: encodedRoles.value.key, kind: StateWriteKind.Put,
          value: encodedRoles.value.value)])

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
  var deletedCount = 0'u64
  var createdProofs = 0'u64
  var deletedProofs = 0'u64
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
      let removed = context.effectDeletedAccountCount.value
      let children = context.effectCreatedAccountCount.value
      if uint64(removed) > uint64(limits.deletedAccounts)-deletedProofs or
          uint64(children) > uint64(limits.createdAccounts)-createdProofs:
        fail(AccumulationBatchError.LimitExceeded) # Bound all inspected facts, including ignored recreation traces.
      deletedProofs += uint64(removed)
      createdProofs += uint64(children)
      for ordinal in 0..<removed:
        if writes.len > high(int) div sizeof(StateWrite)-3:
          fail(AccumulationBatchError.LimitExceeded) # At most metadata/request/preimage deletions accompany one target.
        let target = context.effectDeletedAccountAt(AccumulationDeletedAccountIndex(uint64(
            ordinal))).value
        for id in ids:
          if uint32(id) == uint32(target.service):
            fail(AccumulationBatchError.UnsupportedAccountEffects) # Participating executions/skips need explicit deletion-versus-work semantics.
        let key = chapterServiceKey(StateChapter(255), target.service)
        if prior.lookup(key).error != StateStoreError.None:
          fail(AccumulationBatchError.UnsupportedAccountEffects) # New-and-removed accounts are outside this existing-account deletion contract.
        let finalRecord = accounts.lookup(key)
        if finalRecord.error == StateStoreError.None:
          if finalRecord.value.byteLength != ServiceMetadataBytes or
              not hasCreatedAccount(context, target.service):
            fail(AccumulationBatchError.UnsupportedAccountEffects) # Only genuine selected recreation can cancel a captured removal.
          # Present-final prior IDs are outside m; their foreign replacement is also excluded from n.
        elif finalRecord.error == StateStoreError.MissingKey:
          for deletedKey in [target.requestKey, target.preimageKey]:
            if accounts.lookup(deletedKey).error != StateStoreError.MissingKey:
              fail(AccumulationBatchError.UnsupportedAccountEffects) # No leftover foreign component may escape an actual removal.
          writes.add(StateWrite(key: key, kind: StateWriteKind.Delete))
          writes.add(StateWrite(key: target.requestKey, kind: StateWriteKind.Delete))
          if compareAccountKey(target.requestKey, target.preimageKey) != 0:
            writes.add(StateWrite(key: target.preimageKey,
                kind: StateWriteKind.Delete)) # Preserve the parked namespace alias without duplicate descriptors.
          inc deletedCount
        else:
          fail(AccumulationBatchError.UnsupportedAccountEffects) # An invalid final map cannot prove either presence or absence.
      for ordinal in 0..<children:
        if writes.len > high(int) div sizeof(StateWrite)-2:
          fail(AccumulationBatchError.LimitExceeded) # Each child adds exactly two fully bounded descriptors.
        let child = context.effectCreatedAccountAt(AccumulationCreatedAccountIndex(uint64(
            ordinal))).value
        let key = chapterServiceKey(StateChapter(255), child.service)
        let original = prior.lookup(key)
        if original.error == StateStoreError.None:
          let finalRecord = accounts.lookup(key)
          if not hasDeletedAccount(context, child.service) or
              finalRecord.error != StateStoreError.None:
            fail(AccumulationBatchError.UnsupportedAccountEffects) # Prior-present creation requires matched eject provenance and final presence.
          if finalRecord.value.byteLength != ServiceMetadataBytes:
            fail(AccumulationBatchError.UnsupportedAccountEffects) # No malformed replacement supplies valid selected membership.
          # accpar's n excludes foreign IDs present in the prior; preserve all original target records.
        elif original.error == StateStoreError.MissingKey:
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
        else:
          fail(AccumulationBatchError.UnsupportedAccountEffects) # Default/invalid prior maps cannot authorize creation projection.
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
  var globalWrites = 0
  if executions.len > 0:
    let initial = executions[0].effects.effectsSource.value.initialContext(
        AccumulationDimension.Regular).value
    let assignments = assignmentWrites(selected.value, initial, limits)
    if assignments.error != AccumulationBatchError.None: fail(assignments.error)
    let extra = assignments.value
    if writes.len > high(int) div sizeof(StateWrite)-extra.len: fail(
        AccumulationBatchError.LimitExceeded)
    for write in extra: writes.add(write) # Global and account writes commit together on one private complete-map fork.
    globalWrites = extra.len
  var keys = newSeq[StateKey](writes.len)
  for index, write in writes:
    keys[index] = write.key # Fixed-key scratch detects cross-service or namespace conflicts without copying payloads.
  keys.sort(compareAccountKey)
  for index in 1..<keys.len:
    if compareAccountKey(keys[index-1], keys[index]) == 0:
      fail(AccumulationBatchError.UnsupportedAccountEffects) # No implicit winner for colliding physical account writes.
  AccumulationBatchResult[PreparedAccumulationBatch](status: AccumulationBatchError.None,
    completed: PreparedAccumulationBatch(data: BatchData(inputs: inputs, prior: prior,
      writes: writes, metadataWrites: metadataWrites, assignmentWrites: globalWrites,
      selfBytes: selfBytes,
      selfWriteCount: int(selfWrites), createdCount: int(createdCount), deletedCount: int(
          deletedCount),
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
  ## Apply selected account writes then fnprovide privately; only complete success publishes the caller's store.
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
