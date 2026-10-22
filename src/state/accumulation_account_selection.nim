# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current GP accpar M(s): bind prior accounts to genuine annulment-selected source maps.
## A bounded subset certificate does not claim complete coverage, creation union or publication.
import ../codec/[bounded, state_accounts, state_layout]
import ./[accumulation_annulment, accumulation_outcome, accumulation_effects, store]

type
  AccumulationAccountSelectionIndex* = distinct uint64 ## Requested-account ordinal is distinct from outcome ordinals and service IDs.
  AccumulationAccountOrigin* {.pure.} = enum ## Identity includes absent/annulled supervisor executions.
    Prior, Invoker, Supervisor
  AccumulationAccountSelectionLimits* = object ## Source capture, requested rows and predicate work are independent.
    accounts*, outcomes*, checks*: ElementLimit ## Zero grants only the corresponding empty work.
  AccumulationAccountSelectionInfo* = object ## Copied subset facts never imply complete accpar account coverage.
    accounts*, present*, deleted*, invokers*, supervised*: int ## Actual requested rows, final presence and selected context origins.
    checks*: uint64 ## Identity, metadata and membership operations charged before execution.
  AccumulationAccountSelectionEntry* = object ## Independent copied observations cannot construct an immutable selected row.
    service*: ServiceIndex             ## Always present in the retained common prior.
    origin*: AccumulationAccountOrigin ## Genuine source of the selected account's complete map.
    present*: bool                     ## False is the selected deletion of an existing prior account.
  AccumulationAccountSelectionError* {.pure.} = enum ## Failed alternatives carry only a reason, never a partial map or metadata.
    Uninitialized, None, InvalidSource, UnknownService, DuplicateService, MalformedState,
    LimitExceeded, InvalidIndex, NoAccount, NoOutcome
  SourceRow = object # Fixed source cache reads selected membership counts and accounts from one immutable certificate.
    service: ServiceIndex
    context: AccumulationEffectContext
    accounts: StateStoreSnapshot
    modified: int
    annulled: bool
  AccountRow = object # Metadata bytes and snapshot handles belong to the complete selected source, never a synthesized map.
    entry: AccumulationAccountSelectionEntry
    accounts: StateStoreSnapshot
    metadata: ServiceMetadata
    source: int
  SelectionData = ref object # Retain only fixed copies and their genuine source certificate; no borrowed arrays or cycles.
    source: PreparedAccumulationAnnulment
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
    services: openArray[ServiceIndex], limits: AccumulationAccountSelectionLimits):
    AccumulationAccountSelectionResult[PreparedAccumulationAccountSelection] =
  ## Borrow requested IDs only during this call; immutable source/selected map handles survive caller release.
  template fail(reason: AccumulationAccountSelectionError) =
    return AccumulationAccountSelectionResult[PreparedAccumulationAccountSelection](status: reason)
  let facts = source.annulmentInfo
  if facts.error != AccumulationAnnulmentError.None:
    fail(AccumulationAccountSelectionError.InvalidSource) # No caller-authored cancellation flags or maps.
  let sourceCount = facts.value.outcomes
  if uint64(sourceCount) > uint64(limits.outcomes) or uint64(services.len) > uint64(
      limits.accounts):
    fail(AccumulationAccountSelectionError.LimitExceeded) # Bound both complete descriptor traversals before capture.
  if sourceCount > high(int) div sizeof(SourceRow) or services.len > high(int) div sizeof(AccountRow):
    fail(AccumulationAccountSelectionError.LimitExceeded) # Prove both native allocation extents without multiplying first.
  let prior = source.annulmentPrior.value
  var sources = newSeq[SourceRow](sourceCount)
  for index in 0..<sourceCount:
    let ordinal = AccumulationAnnulmentIndex(uint64(index))
    let decision = source.annulmentDecisionAt(ordinal).value
    sources[index] = SourceRow(service: decision.service, annulled: decision.annulled,
      context: source.annulmentOriginalOutcomeAt(ordinal).value.outcomeContext.value,
      accounts: source.annulmentSelectedAccountsAt(ordinal).value,
      modified: source.annulmentSelectedModifiedCountAt(
          ordinal).value) # Canceled originals contribute no selected membership.
  var rows = newSeq[AccountRow](services.len)
  var work = 0'u64
  var present = 0
  var invokers = 0
  var supervised = 0
  template spend() =
    if work >= uint64(limits.checks): fail(AccumulationAccountSelectionError.LimitExceeded)
    inc work # Charge every identity, metadata and membership operation before executing it.
  for index, service in services:
    for previous in 0..<index:
      spend()
      if uint32(rows[previous].entry.service) == uint32(service):
        fail(AccumulationAccountSelectionError.DuplicateService) # M is a dictionary, never duplicate request rows.
    spend()
    let original = metadata(prior, service)
    if original.error == AccumulationAccountSelectionError.NoAccount:
      fail(AccumulationAccountSelectionError.UnknownService) # This layer implements only existing-prior m, not creation union n.
    if original.error != AccumulationAccountSelectionError.None:
      fail(original.error) # No prior metadata failure exposes an earlier selected row.
    var supervisor = service
    if uint32(original.value.supervisor) != uint32(service):
      spend()
      let nominee = metadata(prior, original.value.supervisor)
      if nominee.error == AccumulationAccountSelectionError.None:
        if uint32(nominee.value.created) == uint32(original.value.supervisorCreated):
          supervisor = original.value.supervisor # Match the original incarnation before considering any post-state account.
      elif nominee.error != AccumulationAccountSelectionError.NoAccount:
        fail(nominee.error) # Missing nominee alone falls back to self.
    var own = -1
    var parent = -1
    for candidate in 0..<sourceCount:
      spend()
      if uint32(sources[candidate].service) == uint32(
          service): own = candidate # Genuine annulment preflight already proved uniqueness.
      spend()
      if uint32(sources[candidate].service) == uint32(
          supervisor): parent = candidate # Supervisor execution may be absent.
    var ownModified = false
    if own >= 0:
      for member in 0..<sources[own].modified:
        spend()
        let changed = sources[own].context.effectModifiedAccountAt(AccumulationModifiedAccountIndex(
            uint64(member))).value
        if uint32(changed) == uint32(service):
          ownModified = true
          break # Only selected membership grants own-context precedence.
    var chosen = parent
    if ownModified: chosen = own # This is exactly M's first branch.
    var accounts = prior
    var origin = AccumulationAccountOrigin.Prior
    if chosen >= 0:
      if not sources[chosen].annulled:
        accounts = sources[chosen].accounts
        if uint32(sources[chosen].service) == uint32(service):
          origin = AccumulationAccountOrigin.Invoker
          inc invokers # Self supervision can choose an unchanged invoking context.
        else:
          origin = AccumulationAccountOrigin.Supervisor
          inc supervised # The selected supervisor may explicitly remove this prior account.
      else:
        chosen = -1 # N's prior state has no retained mutating outcome for account publication.
    spend()
    let selected = metadata(accounts, service)
    var value = default(ServiceMetadata)
    var exists = false
    if selected.error == AccumulationAccountSelectionError.None:
      value = selected.value
      exists = true
      inc present # At most the bounded requested row count can be present.
    elif selected.error != AccumulationAccountSelectionError.NoAccount:
      fail(selected.error) # A selected malformed value never becomes deletion or prior fallback.
    rows[index] = AccountRow(entry: AccumulationAccountSelectionEntry(service: service,
      origin: origin, present: exists), accounts: accounts, metadata: value, source: chosen)
  AccumulationAccountSelectionResult[PreparedAccumulationAccountSelection](
    status: AccumulationAccountSelectionError.None,
    completed: PreparedAccumulationAccountSelection(data: SelectionData(source: source, rows: rows,
      info: AccumulationAccountSelectionInfo(accounts: rows.len, present: present,
        deleted: rows.len-present, invokers: invokers, supervised: supervised, checks: work))))

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
  ## Retain only the genuine nonannulled producer; identity has no usable mutating outcome.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAccountSelectionError.None: return AccumulationAccountSelectionResult[
      AccumulationOutcome](status: row.error) # No substitute original execution.
  if row.value.source < 0: return AccumulationAccountSelectionResult[AccumulationOutcome](
      status: AccumulationAccountSelectionError.NoOutcome) # Missing/annulled supervisor is prior identity.
  let source = plan.accountSelectionSource.value
  let original = source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(
      row.value.source))).value
  AccumulationAccountSelectionResult[AccumulationOutcome](
      status: AccumulationAccountSelectionError.None, completed: original)
