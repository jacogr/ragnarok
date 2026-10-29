# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current GP accpar M(s): bind prior accounts to genuine annulment-selected source maps.
## A bounded subset certificate does not claim complete coverage, creation union or publication.
import ../../../codec/bounded
import ../../../codec/state/[accounts as state_accounts, layout as state_layout]
import ../../../codec/header
import ../[annulment as accumulation_annulment, outcome as accumulation_outcome,
    effects as accumulation_effects, skip as accumulation_skip, service as accumulation_service,
    inputs as accumulation_inputs]
import ../../store

type
  AccumulationAccountSelectionIndex* = distinct uint64 ## Requested-account ordinal is distinct from outcome ordinals and service IDs.
  AccumulationAccountOrigin* {.pure.} = enum ## Identity includes absent/annulled supervisor executions.
    Prior, Invoker, Supervisor, Skipped
  AccumulationAccountSelectionLimits* = object ## Source capture, requested rows and predicate work are independent.
    accounts*, outcomes*, checks*: ElementLimit ## Zero grants only the corresponding empty work.
    skipped*: ElementLimit ## Explicit independent ceiling for retained certified non-executing participants.
  AccumulationAccountSelectionInfo* = object ## Copied subset facts never imply complete accpar account coverage.
    accounts*, present*, deleted*, invokers*, supervised*: int ## Actual requested rows, final presence and selected context origins.
    skippedSources*, skipped*: int ## Captured certified skips and selected skipped account rows remain distinct from executed contexts.
    checks*: uint64 ## Identity, metadata and membership operations charged before execution.
  AccumulationAccountSelectionEntry* = object ## Independent copied observations cannot construct an immutable selected row.
    service*: ServiceIndex             ## Always present in the retained common prior.
    origin*: AccumulationAccountOrigin ## Genuine source of the selected account's complete map.
    present*: bool                     ## False is the selected deletion of an existing prior account.
  AccumulationAccountSelectionError* {.pure.} = enum ## Failed alternatives carry only a reason, never a partial map or metadata.
    Uninitialized, None, InvalidSource, UnknownService, DuplicateService, MalformedState,
    LimitExceeded, InvalidIndex, NoAccount, NoOutcome, NoExecution, NoSkipped, SourceMismatch, UnsafeCreditSchedule
  SourceRow = object # Fixed source cache reads selected membership counts and accounts from one immutable certificate.
    service: ServiceIndex
    context: AccumulationEffectContext
    accounts: StateStoreSnapshot
    modified: int
    annulled: bool
    isSkipped: bool
    skipped: SkippedAccumulation
  AccountRow = object # Metadata bytes and snapshot handles belong to the complete selected source, never a synthesized map.
    entry: AccumulationAccountSelectionEntry
    accounts: StateStoreSnapshot
    metadata: ServiceMetadata
    source: int
    skipped: SkippedAccumulation
  SelectionData = ref object # Retain only fixed copies and their genuine source certificate; no borrowed arrays or cycles.
    source: PreparedAccumulationAnnulment
    skipped: seq[SkippedAccumulation]
    rows: seq[AccountRow]
    info: AccumulationAccountSelectionInfo
  PreparedAccumulationAccountSelection* = object ## Only complete checked preparation constructs a prior-account selection plan.
    data: nil SelectionData
  AccumulationAccountSelectionResult*[T] = object ## Successful extraction is private, guarded and cannot be retagged.
    case status: AccumulationAccountSelectionError
    of None:
      completed: T # No inactive successful payload is exposed.
    else:
      discard      # Default/refused alternatives retain reasons alone.

func error*[T](outcome: AccumulationAccountSelectionResult[T]): AccumulationAccountSelectionError =
  ## Inspect the reason without granting result mutation.
  outcome.status
func value*[T](outcome: AccumulationAccountSelectionResult[T]): T {.inline,
    requires: outcome.status == AccumulationAccountSelectionError.None.} =
  ## Extract only complete selected success under checked optimized contracts.
  outcome.completed
proc metadata(state: StateStoreSnapshot, service: ServiceIndex): AccumulationAccountSelectionResult[
    ServiceMetadata] =
  ## Preserve selected absence separately from malformed metadata and require exact canonical width.
  let found = state.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error == StateStoreError.MissingKey:
    return AccumulationAccountSelectionResult[ServiceMetadata](
        status: AccumulationAccountSelectionError.NoAccount) # Selected deletion is not identity.
  if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
    return AccumulationAccountSelectionResult[ServiceMetadata](
        status: AccumulationAccountSelectionError.MalformedState) # No repaired or truncated account.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    return AccumulationAccountSelectionResult[ServiceMetadata](
        status: AccumulationAccountSelectionError.MalformedState) # Require the canonical version too.
  AccumulationAccountSelectionResult[ServiceMetadata](
      status: AccumulationAccountSelectionError.None, completed: decoded.value.metadata)

proc prepareAccumulationAccountSelection*(source: PreparedAccumulationAnnulment,
    services: openArray[ServiceIndex], limits: AccumulationAccountSelectionLimits,
    skipped: openArray[SkippedAccumulation] = []):
    AccumulationAccountSelectionResult[PreparedAccumulationAccountSelection] =
  ## Borrow requested IDs/skips only during this call; retain genuine immutable source and selected map owners.
  template fail(reason: AccumulationAccountSelectionError) =
    return AccumulationAccountSelectionResult[PreparedAccumulationAccountSelection](status: reason)
  let facts = source.annulmentInfo
  if facts.error != AccumulationAnnulmentError.None:
    fail(AccumulationAccountSelectionError.InvalidSource) # No caller-authored cancellation flags or maps.
  let outcomes = facts.value.outcomes
  if uint64(outcomes) > uint64(limits.outcomes) or uint64(services.len) > uint64(limits.accounts):
    fail(AccumulationAccountSelectionError.LimitExceeded) # Bound original outcome and requested-row traversals.
  if uint64(skipped.len) > uint64(limits.skipped) or skipped.len > high(int)-outcomes:
    fail(AccumulationAccountSelectionError.LimitExceeded) # Prove combined producer addition before native allocation.
  let sourceCount = outcomes+skipped.len
  if sourceCount > high(int) div sizeof(SourceRow) or services.len > high(int) div sizeof(AccountRow):
    fail(AccumulationAccountSelectionError.LimitExceeded) # Every source/skip/row descriptor extent fits before allocation.
  let prior = source.annulmentPrior.value
  let inputs = source.annulmentInputs.value
  var sources = newSeq[SourceRow](sourceCount)
  var work = 0'u64
  template spend() =
    if work >= uint64(limits.checks): fail(AccumulationAccountSelectionError.LimitExceeded)
    inc work # Charge identity, metadata and membership operations before executing them.
  for index in 0..<outcomes:
    let ordinal = AccumulationAnnulmentIndex(uint64(index))
    let decision = source.annulmentDecisionAt(ordinal).value
    sources[index] = SourceRow(service: decision.service, annulled: decision.annulled,
      context: source.annulmentOriginalOutcomeAt(ordinal).value.outcomeContext.value,
      accounts: source.annulmentSelectedAccountsAt(ordinal).value,
      modified: source.annulmentSelectedModifiedCountAt(ordinal).value,
      isSkipped: false) # Canceled originals contribute no selected membership.
  var hasSlot = false
  var slot = HeaderSlot(0)
  let invocationSlot = source.annulmentSlot
  if invocationSlot.error == AccumulationAnnulmentError.None:
    slot = invocationSlot.value
    hasSlot = true # Existing executed sources already share one bootstrap slot/entropy.
  var retained = newSeq[SkippedAccumulation](skipped.len)
  for index, item in skipped:
    let candidate = item.skipService
    if candidate.error != AccumulationSkipError.None:
      fail(AccumulationAccountSelectionError.InvalidSource) # A default skip cannot fabricate a non-executing participant.
    let service = candidate.value
    if not service.serviceSourceMatches(inputs, prior):
      fail(AccumulationAccountSelectionError.SourceMismatch) # Equal roots or account bytes do not replace exact input/map owners.
    let info = service.serviceInfo.value
    spend()
    if hasSlot:
      if uint32(info.slot) != uint32(slot):
        fail(AccumulationAccountSelectionError.SourceMismatch) # A different invocation time cannot contribute credit to this selected entry.
    else:
      slot = info.slot
      hasSlot = true # Skip-only sources bind the first genuine non-executing invocation time.
    let position = outcomes+index
    for previous in 0..<position:
      spend()
      if uint32(sources[previous].service) == uint32(info.service):
        fail(AccumulationAccountSelectionError.DuplicateService) # Executed and skipped coverage cannot name the same participant twice.
    if info.transfers != 0:
      spend()
      let own = metadata(prior, info.service)
      if own.error != AccumulationAccountSelectionError.None:
        fail(own.error) # The certified source requires its real original account.
      var supervisor = info.service
      if uint32(own.value.supervisor) != uint32(info.service):
        spend()
        let nominee = metadata(prior, own.value.supervisor)
        if nominee.error == AccumulationAccountSelectionError.None:
          if uint32(nominee.value.created) == uint32(own.value.supervisorCreated):
            supervisor = own.value.supervisor # Resolve only the actual prior incarnation.
        elif nominee.error != AccumulationAccountSelectionError.NoAccount:
          fail(nominee.error) # Corrupt nominee metadata never implies self supervision.
      if uint32(supervisor) != uint32(info.service):
        for active in 0..<inputs.invocationServiceCount.value:
          spend()
          let participant = inputs.invocationServiceAt(InvocationServiceIndex(uint64(
              active))).value.service
          if uint32(participant) == uint32(supervisor):
            fail(AccumulationAccountSelectionError.UnsafeCreditSchedule) # fnpartition must defer junior credit while its supervisor is in this input group set.
    sources[position] = SourceRow(service: info.service, accounts: item.skipState.value,
      modified: (if info.transfers == 0: 0 else: 1), isSkipped: true,
      skipped: item, annulled: false) # Incoming records mark self even when their amount is zero.
    retained[index] = item # Retain every validated skip, including those not requested as output rows.
  var rows = newSeq[AccountRow](services.len)
  var present = 0
  var invokers = 0
  var supervised = 0
  var selectedSkips = 0
  for index, service in services:
    for previous in 0..<index:
      spend()
      if uint32(rows[previous].entry.service) == uint32(service):
        fail(AccumulationAccountSelectionError.DuplicateService) # M is a dictionary, never duplicate request rows.
    spend()
    let original = metadata(prior, service)
    if original.error == AccumulationAccountSelectionError.NoAccount:
      fail(AccumulationAccountSelectionError.UnknownService) # This layer selects existing-prior m, not creation union n.
    if original.error != AccumulationAccountSelectionError.None:
      fail(original.error) # No malformed prior account exposes an earlier selected row.
    var supervisor = service
    if uint32(original.value.supervisor) != uint32(service):
      spend()
      let nominee = metadata(prior, original.value.supervisor)
      if nominee.error == AccumulationAccountSelectionError.None:
        if uint32(nominee.value.created) == uint32(original.value.supervisorCreated):
          supervisor = original.value.supervisor # Resolve from the common prior, never a changed candidate.
      elif nominee.error != AccumulationAccountSelectionError.NoAccount:
        fail(nominee.error) # Only a missing nominee falls back to self.
    var own = -1
    var parent = -1
    for candidate in 0..<sourceCount:
      spend()
      if uint32(sources[candidate].service) == uint32(
          service): own = candidate # Unique participant preflight makes this unambiguous.
      spend()
      if uint32(sources[candidate].service) == uint32(
          supervisor): parent = candidate # Missing supervisor remains prior identity.
    var ownModified = false
    if own >= 0:
      if sources[own].isSkipped:
        ownModified = sources[own].modified != 0 # Incoming transfer membership alone grants skipped self-credit precedence.
      else:
        for member in 0..<sources[own].modified:
          spend()
          let changed = sources[own].context.effectModifiedAccountAt(
              AccumulationModifiedAccountIndex(uint64(member))).value
          if uint32(changed) == uint32(service):
            ownModified = true
            break # Only selected executed membership grants this own-context branch.
    var chosen = parent
    if ownModified: chosen = own # Exactly M's first branch, including genuine skipped credit.
    var accounts = prior
    var origin = AccumulationAccountOrigin.Prior
    var selectedSkip = default(SkippedAccumulation)
    if chosen >= 0:
      if sources[chosen].isSkipped:
        if uint32(sources[chosen].service) == uint32(service):
          accounts = sources[chosen].accounts
          selectedSkip = sources[chosen].skipped
          origin = AccumulationAccountOrigin.Skipped
          inc selectedSkips # Own skipped state is real post-credit state, never a fabricated executed outcome.
        chosen = -1 # A skip cannot modify another account; prior identity is equivalent for a supervised target.
      elif not sources[chosen].annulled:
        accounts = sources[chosen].accounts
        if uint32(sources[chosen].service) == uint32(service):
          origin = AccumulationAccountOrigin.Invoker
          inc invokers # Self supervision can choose an unchanged invoking context.
        else:
          origin = AccumulationAccountOrigin.Supervisor
          inc supervised # A genuine selected supervisor may explicitly delete this prior account.
      else:
        chosen = -1 # N's prior state grants no mutating producer.
    spend()
    let selected = metadata(accounts, service)
    var value = default(ServiceMetadata)
    var exists = false
    if selected.error == AccumulationAccountSelectionError.None:
      value = selected.value
      exists = true
      inc present # Bounded requested row count also bounds this increment.
    elif selected.error != AccumulationAccountSelectionError.NoAccount:
      fail(selected.error) # Malformed selected metadata never becomes deletion or prior fallback.
    rows[index] = AccountRow(entry: AccumulationAccountSelectionEntry(service: service,
      origin: origin, present: exists), accounts: accounts, metadata: value,
      source: chosen, skipped: selectedSkip)
  AccumulationAccountSelectionResult[PreparedAccumulationAccountSelection](
    status: AccumulationAccountSelectionError.None,
    completed: PreparedAccumulationAccountSelection(data: SelectionData(source: source,
      skipped: retained, rows: rows,
      info: AccumulationAccountSelectionInfo(accounts: rows.len, present: present,
        deleted: rows.len-present, invokers: invokers, supervised: supervised,
        skippedSources: retained.len, skipped: selectedSkips, checks: work))))

proc accountSelectionInfo*(plan: PreparedAccumulationAccountSelection): AccumulationAccountSelectionResult[
    AccumulationAccountSelectionInfo] =
  ## Copy subset accounting without exposing mutable selected rows.
  let data = plan.data
  if data == nil: return AccumulationAccountSelectionResult[AccumulationAccountSelectionInfo](
      status: AccumulationAccountSelectionError.Uninitialized) # No fabricated empty certificate.
  AccumulationAccountSelectionResult[AccumulationAccountSelectionInfo](
      status: AccumulationAccountSelectionError.None, completed: data.info)
proc accountSelectionSource*(plan: PreparedAccumulationAccountSelection): AccumulationAccountSelectionResult[
    PreparedAccumulationAnnulment] =
  ## Retain the exact conflict decisions which authorized every selected row.
  let data = plan.data
  if data == nil: return AccumulationAccountSelectionResult[PreparedAccumulationAnnulment](
      status: AccumulationAccountSelectionError.Uninitialized) # Defaults retain no source certificate.
  AccumulationAccountSelectionResult[PreparedAccumulationAnnulment](
      status: AccumulationAccountSelectionError.None, completed: data.source)
proc selectedRow(plan: PreparedAccumulationAccountSelection,
    index: AccumulationAccountSelectionIndex): AccumulationAccountSelectionResult[AccountRow] =
  ## Guard full-width ordinals before narrowing and return only independent immutable-handle copies.
  let data = plan.data
  if data == nil: return AccumulationAccountSelectionResult[AccountRow](
      status: AccumulationAccountSelectionError.Uninitialized) # No default row.
  if uint64(index) >= uint64(data.rows.len): return AccumulationAccountSelectionResult[AccountRow](
      status: AccumulationAccountSelectionError.InvalidIndex) # Upper-half ordinals cannot wrap into selected rows.
  AccumulationAccountSelectionResult[AccountRow](status: AccumulationAccountSelectionError.None,
      completed: data.rows[int(uint64(index))])
proc selectedAccountAt*(plan: PreparedAccumulationAccountSelection,
    index: AccumulationAccountSelectionIndex): AccumulationAccountSelectionResult[
    AccumulationAccountSelectionEntry] =
  ## Copy final presence and origin without granting mutable selected storage.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAccountSelectionError.None: return AccumulationAccountSelectionResult[
      AccumulationAccountSelectionEntry](status: row.error) # Preserve default/bounds refusal.
  AccumulationAccountSelectionResult[AccumulationAccountSelectionEntry](
      status: AccumulationAccountSelectionError.None, completed: row.value.entry)
proc selectedAccountSnapshotAt*(plan: PreparedAccumulationAccountSelection,
    index: AccumulationAccountSelectionIndex): AccumulationAccountSelectionResult[
    StateStoreSnapshot] =
  ## Retain the complete source map for this logical account; it is not an already merged batch map.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAccountSelectionError.None: return AccumulationAccountSelectionResult[
      StateStoreSnapshot](status: row.error) # No map payload on refusal.
  AccumulationAccountSelectionResult[StateStoreSnapshot](
      status: AccumulationAccountSelectionError.None, completed: row.value.accounts)
proc selectedAccountMetadataAt*(plan: PreparedAccumulationAccountSelection,
    index: AccumulationAccountSelectionIndex): AccumulationAccountSelectionResult[ServiceMetadata] =
  ## Copy actual selected metadata; deletion has a typed absent result, never zero metadata.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAccountSelectionError.None: return AccumulationAccountSelectionResult[
      ServiceMetadata](status: row.error) # Default/bounds refusal has no metadata.
  if not row.value.entry.present: return AccumulationAccountSelectionResult[ServiceMetadata](
      status: AccumulationAccountSelectionError.NoAccount) # Deleted accounts carry no successful value.
  AccumulationAccountSelectionResult[ServiceMetadata](
      status: AccumulationAccountSelectionError.None, completed: row.value.metadata)
proc selectedAccountOutcomeAt*(plan: PreparedAccumulationAccountSelection,
    index: AccumulationAccountSelectionIndex): AccumulationAccountSelectionResult[
    AccumulationOutcome] =
  ## Retain a selected executed producer; identity and certified skips have distinct typed refusals.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAccountSelectionError.None: return AccumulationAccountSelectionResult[
      AccumulationOutcome](status: row.error) # No substitute original execution.
  if row.value.entry.origin == AccumulationAccountOrigin.Skipped:
    return AccumulationAccountSelectionResult[AccumulationOutcome](
        status: AccumulationAccountSelectionError.NoExecution) # Genuine skipped credit never carries a fake executed outcome.
  if row.value.source < 0: return AccumulationAccountSelectionResult[AccumulationOutcome](
      status: AccumulationAccountSelectionError.NoOutcome) # Missing/annulled supervisor is prior identity.
  let source = plan.accountSelectionSource.value
  let original = source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(
      row.value.source))).value
  AccumulationAccountSelectionResult[AccumulationOutcome](
      status: AccumulationAccountSelectionError.None, completed: original)

proc selectedAccountSkipAt*(plan: PreparedAccumulationAccountSelection,
    index: AccumulationAccountSelectionIndex): AccumulationAccountSelectionResult[
        SkippedAccumulation] =
  ## Retain only a genuinely selected non-executing participant; other origins have no skipped proof.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAccountSelectionError.None:
    return AccumulationAccountSelectionResult[SkippedAccumulation](
        status: row.error) # Preserve default/bounds refusal without a payload.
  if row.value.entry.origin != AccumulationAccountOrigin.Skipped:
    return AccumulationAccountSelectionResult[SkippedAccumulation](
        status: AccumulationAccountSelectionError.NoSkipped) # Prior/executed origins cannot fabricate unavailable-code completion.
  AccumulationAccountSelectionResult[SkippedAccumulation](
      status: AccumulationAccountSelectionError.None, completed: row.value.skipped)
