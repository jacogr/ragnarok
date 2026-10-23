# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current GP accpar conflict annulment over genuine common-source normalized outcomes.
## Pure immutable certificates distinguish original effects from selected state/count observations.
import ../codec/[bounded, state_accounts, state_layout, header, state_safrole]
import ./[accumulation_outcome, accumulation_effects, accumulation_context,
  accumulation_invocation, accumulation_service, accumulation_inputs, store]

type
  AccumulationAnnulmentIndex* = distinct uint64 ## Input outcome ordinal cannot substitute a service identity.
  AccumulationAnnulmentLimits* = object         ## Explicit source, membership and predicate work ceilings.
    outcomes*, modified*, checks*: ElementLimit ## Zero grants only the corresponding empty work.
  AccumulationAnnulmentInfo* = object ## Copied accounting does not certify batch coverage or publication.
    outcomes*, modified*, annulled*: int ## Actual source count, original memberships and selected cancellations.
    checks*: uint64 ## Metadata, identity and membership operations charged before execution.
  AccumulationAnnulmentDecision* = object ## Copied observations cannot construct or retag the immutable certificate.
    service*, supervisor*: ServiceIndex ## Effective supervision is resolved against the exact common prior.
    annulled*: bool ## True only for the two original modified-set conflict with a different supervisor.
  AccumulationAnnulmentError* {.pure.} = enum ## Refused/default alternatives carry no source, state or decision payload.
    Uninitialized, None, InvalidInputs, InvalidState, InvalidOutcome, SourceMismatch,
    DuplicateService, MalformedState, LimitExceeded, InvalidIndex, NoInvocationSlot,
      StorageFactsDisabled, RequestFactsDisabled
  OutcomeRow = object # Immutable rows retain only genuine original outcomes and their calculated decision.
    outcome: AccumulationOutcome
    decision: AccumulationAnnulmentDecision
    modified: int
  AnnulmentData = ref object # Fixed acyclic owner retains original provenance without borrowing caller descriptors.
    inputs: PreparedAccumulationInputs
    prior: StateStoreSnapshot
    rows: seq[OutcomeRow]
    info: AccumulationAnnulmentInfo
    slot: HeaderSlot
  PreparedAccumulationAnnulment* = object ## Only successful common-source preparation constructs a certificate.
    data: nil AnnulmentData
  AccumulationAnnulmentResult*[T] = object ## Successful payloads are private and extraction requires selected success.
    case status: AccumulationAnnulmentError
    of None:
      completed: T # No public variant payload permits fabricated or inactive extraction.
    else:
      discard      # Refusal retains only its typed reason.

func sameAccumulationAnnulment*(left, right: PreparedAccumulationAnnulment): bool =
  ## Compare initialized certificate identity; equal contents or two defaults cannot replace one checked source.
  left.data != nil and left.data == right.data

func error*[T](outcome: AccumulationAnnulmentResult[T]): AccumulationAnnulmentError =
  ## Inspect the reason without granting result mutation.
  outcome.status
func value*[T](outcome: AccumulationAnnulmentResult[T]): T {.inline,
    requires: outcome.status == AccumulationAnnulmentError.None.} =
  ## Extract only a complete selected success under checked optimized contracts.
  outcome.completed

proc account(prior: StateStoreSnapshot, service: ServiceIndex): AccumulationAnnulmentResult[
    ServiceMetadata] =
  ## Preserve missing nominees separately from malformed complete canonical metadata.
  let found = prior.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error == StateStoreError.MissingKey:
    return AccumulationAnnulmentResult[ServiceMetadata](
        status: AccumulationAnnulmentError.InvalidOutcome) # A missing nominee has an explicit caller fallback.
  if found.error != StateStoreError.None:
    return AccumulationAnnulmentResult[ServiceMetadata](
        status: AccumulationAnnulmentError.InvalidState) # Defaults/backend failures never imply missing accounts.
  if found.value.byteLength != ServiceMetadataBytes:
    return AccumulationAnnulmentResult[ServiceMetadata](
        status: AccumulationAnnulmentError.MalformedState) # Exact fixed metadata length is mandatory.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    return AccumulationAnnulmentResult[ServiceMetadata](
        status: AccumulationAnnulmentError.MalformedState) # No corrupt nominee grants self supervision.
  AccumulationAnnulmentResult[ServiceMetadata](status: AccumulationAnnulmentError.None,
      completed: decoded.value.metadata)

proc contains(context: AccumulationEffectContext, count: int, service: ServiceIndex,
    work: var uint64, ceiling: ElementLimit): AccumulationAnnulmentResult[bool] =
  ## Scan already bounded immutable membership with explicit caller-owned work accounting.
  for index in 0..<count:
    if work >= uint64(ceiling):
      return AccumulationAnnulmentResult[bool](status: AccumulationAnnulmentError.LimitExceeded) # Charge before accessing or comparing the next identity.
    inc work
    let member = context.effectModifiedAccountAt(AccumulationModifiedAccountIndex(uint64(index))).value
    if uint32(member) == uint32(service):
      return AccumulationAnnulmentResult[bool](status: AccumulationAnnulmentError.None,
          completed: true) # Genuine successful membership, not state-root equality.
  AccumulationAnnulmentResult[bool](status: AccumulationAnnulmentError.None, completed: false)

proc prepareAccumulationAnnulment*(inputs: PreparedAccumulationInputs, prior: StateStoreSnapshot,
    outcomes: openArray[AccumulationOutcome], limits: AccumulationAnnulmentLimits):
    AccumulationAnnulmentResult[PreparedAccumulationAnnulment] =
  ## Borrow stable source descriptors for this call; retain genuine immutable copies only after full validation.
  template fail(reason: AccumulationAnnulmentError) =
    return AccumulationAnnulmentResult[PreparedAccumulationAnnulment](status: reason)
  if inputs.invocationServiceCount.error != AccumulationInputError.None:
    fail(AccumulationAnnulmentError.InvalidInputs) # No default input provenance.
  if not sameStateSnapshot(prior, prior):
    fail(AccumulationAnnulmentError.InvalidState) # An initialized complete map is required even for empty work.
  if uint64(outcomes.len) > uint64(limits.outcomes) or outcomes.len > high(int) div sizeof(OutcomeRow):
    fail(AccumulationAnnulmentError.LimitExceeded) # Prove source traversal and native allocation extent before copying.
  var rows = newSeq[OutcomeRow](outcomes.len)
  var modified = 0'u64
  var work = 0'u64
  var slot = HeaderSlot(0)
  var entropy = default(StateEntropyWord)
  template spend() =
    if work >= uint64(limits.checks): fail(AccumulationAnnulmentError.LimitExceeded)
    inc work # The preincrement comparison proves this natural fits.
  for index, original in outcomes:
    let info = original.outcomeInfo
    if info.error != AccumulationOutcomeError.None:
      fail(AccumulationAnnulmentError.InvalidOutcome) # No caller-authored completion metadata.
    let context = original.outcomeContext.value
    let initial = context.effectInitialContext.value
    let invocation = initial.contextInvocation.value
    let source = invocation.bootstrapService.value
    if not source.serviceSourceMatches(inputs, prior):
      fail(AccumulationAnnulmentError.SourceMismatch) # Equal roots or service metadata cannot replace original owner identity.
    let frame = invocation.bootstrapInfo.value
    if index == 0:
      slot = frame.slot
      entropy = frame.entropy # Bind the first actual invocation frame; empty sources expose no invented slot.
    else:
      spend()
      if uint32(frame.slot) != uint32(slot):
        fail(AccumulationAnnulmentError.SourceMismatch) # Common input/map owners cannot authorize mixing invocation times.
      spend()
      if array[32, byte](frame.entropy) != array[32, byte](entropy):
        fail(AccumulationAnnulmentError.SourceMismatch) # Candidate allocation entropy belongs to the same actual invocation frame.
    let count = context.effectModifiedAccountCount
    if count.error != AccumulationEffectError.None:
      fail(AccumulationAnnulmentError.InvalidOutcome) # Disabled tracking cannot impersonate an empty modified set.
    if uint64(count.value) > uint64(limits.modified)-modified:
      fail(AccumulationAnnulmentError.LimitExceeded) # Bound the total before adding under wrapping arithmetic.
    modified += uint64(count.value)
    for earlier in 0..<index:
      spend()
      if uint32(rows[earlier].decision.service) == uint32(info.value.service):
        fail(AccumulationAnnulmentError.DuplicateService) # One original outcome per invoker, independent of array order.
    rows[index] = OutcomeRow(outcome: original, modified: count.value,
      decision: AccumulationAnnulmentDecision(service: info.value.service,
          supervisor: info.value.service, annulled: false))
  if modified > uint64(high(int)):
    fail(AccumulationAnnulmentError.LimitExceeded) # The copied public total must fit its native count domain.
  var annulled = 0
  for index in 0..<rows.len:
    let service = rows[index].decision.service
    spend()
    let own = account(prior, service)
    if own.error != AccumulationAnnulmentError.None: fail(
        own.error) # Every invoker must have its original present account.
    var supervisor = service
    if uint32(own.value.supervisor) != uint32(service):
      spend()
      let nominee = account(prior, own.value.supervisor)
      if nominee.error == AccumulationAnnulmentError.None:
        if uint32(nominee.value.created) == uint32(own.value.supervisorCreated):
          supervisor = own.value.supervisor # Matching prior incarnation grants effective supervision.
      elif nominee.error != AccumulationAnnulmentError.InvalidOutcome:
        fail(nominee.error) # Missing nominee alone falls back to self.
    rows[index].decision.supervisor = supervisor
    if uint32(supervisor) == uint32(service): continue # Self supervision explicitly excludes cancellation.
    let selfModified = contains(rows[index].outcome.outcomeContext.value, rows[index].modified,
      service, work, limits.checks)
    if selfModified.error != AccumulationAnnulmentError.None: fail(selfModified.error)
    if not selfModified.value: continue # A supervisor-only change cannot cancel an untouched junior execution.
    for candidate in 0..<rows.len:
      spend()
      if uint32(rows[candidate].decision.service) != uint32(
          supervisor): continue # Find the actual original supervisor execution.
      let parentModified = contains(rows[candidate].outcome.outcomeContext.value,
        rows[candidate].modified, service, work, limits.checks)
      if parentModified.error != AccumulationAnnulmentError.None: fail(parentModified.error)
      if parentModified.value:
        rows[index].decision.annulled = true
        inc annulled # Read original modified sets even if the parent is itself annulled.
      break # Unique-source preflight proves no second supervisor execution exists.
  AccumulationAnnulmentResult[PreparedAccumulationAnnulment](
    status: AccumulationAnnulmentError.None,
    completed: PreparedAccumulationAnnulment(data: AnnulmentData(inputs: inputs, prior: prior,
      rows: rows, slot: slot, info: AccumulationAnnulmentInfo(outcomes: rows.len, modified: int(
          modified),
        annulled: annulled, checks: work))))

proc annulmentInfo*(plan: PreparedAccumulationAnnulment): AccumulationAnnulmentResult[
    AccumulationAnnulmentInfo] =
  ## Copy preparation accounting without exposing row storage or source descriptors.
  let data = plan.data
  if data == nil: return AccumulationAnnulmentResult[AccumulationAnnulmentInfo](
      status: AccumulationAnnulmentError.Uninitialized) # No fabricated empty certificate.
  AccumulationAnnulmentResult[AccumulationAnnulmentInfo](status: AccumulationAnnulmentError.None,
      completed: data.info)
proc annulmentPrior*(plan: PreparedAccumulationAnnulment): AccumulationAnnulmentResult[
    StateStoreSnapshot] =
  ## Retain the exact complete prior used by every effective-supervisor predicate.
  let data = plan.data
  if data == nil: return AccumulationAnnulmentResult[StateStoreSnapshot](
      status: AccumulationAnnulmentError.Uninitialized) # Defaults carry no prior.
  AccumulationAnnulmentResult[StateStoreSnapshot](status: AccumulationAnnulmentError.None,
      completed: data.prior)
proc selectedRow(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex): AccumulationAnnulmentResult[OutcomeRow] =
  ## Guard full-width ordinals before narrowing; returned rows are independent immutable-handle copies.
  let data = plan.data
  if data == nil: return AccumulationAnnulmentResult[OutcomeRow](
      status: AccumulationAnnulmentError.Uninitialized) # No default row.
  if uint64(index) >= uint64(data.rows.len): return AccumulationAnnulmentResult[OutcomeRow](
      status: AccumulationAnnulmentError.InvalidIndex) # Includes upper-half naturals.
  AccumulationAnnulmentResult[OutcomeRow](status: AccumulationAnnulmentError.None,
      completed: data.rows[int(uint64(index))])
proc annulmentDecisionAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex): AccumulationAnnulmentResult[AccumulationAnnulmentDecision] =
  ## Copy the selected conflict decision; mutating it cannot alter the certificate.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAnnulmentError.None: return AccumulationAnnulmentResult[
      AccumulationAnnulmentDecision](status: row.error) # Preserve default/bounds refusal.
  AccumulationAnnulmentResult[AccumulationAnnulmentDecision](
      status: AccumulationAnnulmentError.None, completed: row.value.decision)
proc annulmentOriginalOutcomeAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex): AccumulationAnnulmentResult[AccumulationOutcome] =
  ## Retain original provenance and provisions explicitly; this is never a selected-state substitute.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAnnulmentError.None: return AccumulationAnnulmentResult[
      AccumulationOutcome](status: row.error) # No substituted raw execution.
  AccumulationAnnulmentResult[AccumulationOutcome](status: AccumulationAnnulmentError.None,
      completed: row.value.outcome)
proc annulmentSelectedInfoAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex): AccumulationAnnulmentResult[AccumulationOutcomeInfo] =
  ## N preserves actual gas/provisions and clears selected outgoing transfers and yield presence.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAnnulmentError.None: return AccumulationAnnulmentResult[
      AccumulationOutcomeInfo](status: row.error) # No fabricated selected completion.
  var info = row.value.outcome.outcomeInfo.value
  if row.value.decision.annulled:
    info.transfers = 0
    info.hasYield = false # Other source facts remain unchanged by conflict annulment.
  AccumulationAnnulmentResult[AccumulationOutcomeInfo](status: AccumulationAnnulmentError.None,
      completed: info)
proc annulmentSelectedAccountsAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex): AccumulationAnnulmentResult[StateStoreSnapshot] =
  ## N restores the common prior; retained outcomes keep their actual terminal-selected complete account map.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAnnulmentError.None: return AccumulationAnnulmentResult[
      StateStoreSnapshot](status: row.error) # No state payload on refusal.
  let accounts = if row.value.decision.annulled: plan.annulmentPrior.value else: row.value.outcome.outcomeContext.value.effectAccounts.value
  AccumulationAnnulmentResult[StateStoreSnapshot](status: AccumulationAnnulmentError.None,
      completed: accounts)
proc annulmentSelectedModifiedCountAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex): AccumulationAnnulmentResult[int] =
  ## N clears modification membership without rewriting the original genuine outcome.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAnnulmentError.None: return AccumulationAnnulmentResult[int](
      status: row.error) # No fabricated empty modified set.
  let count = if row.value.decision.annulled: 0 else: row.value.modified
  AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.None, completed: count)

proc annulmentInputs*(plan: PreparedAccumulationAnnulment): AccumulationAnnulmentResult[
    PreparedAccumulationInputs] =
  ## Retain the exact input owner for validating additional certified non-executing participants.
  let data = plan.data
  if data == nil: return AccumulationAnnulmentResult[PreparedAccumulationInputs](
      status: AccumulationAnnulmentError.Uninitialized) # No default provenance.
  AccumulationAnnulmentResult[PreparedAccumulationInputs](status: AccumulationAnnulmentError.None,
      completed: data.inputs)
proc annulmentSlot*(plan: PreparedAccumulationAnnulment): AccumulationAnnulmentResult[HeaderSlot] =
  ## Copy the shared actual invocation time; initialized empty sources have no invented slot.
  let data = plan.data
  if data == nil: return AccumulationAnnulmentResult[HeaderSlot](
      status: AccumulationAnnulmentError.Uninitialized) # Default differs from a genuine empty source.
  if data.rows.len == 0: return AccumulationAnnulmentResult[HeaderSlot](
      status: AccumulationAnnulmentError.NoInvocationSlot) # A later skip-only adapter must bind its own real slots.
  AccumulationAnnulmentResult[HeaderSlot](status: AccumulationAnnulmentError.None,
      completed: data.slot)

proc annulmentSelectedStorageFactCountAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex): AccumulationAnnulmentResult[int] =
  ## Annulled executions contribute a proven empty selected trace; surviving executions require explicit enabled raw identity capture.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAnnulmentError.None:
    return AccumulationAnnulmentResult[int](status: row.error)
  if row.value.decision.annulled:
    return AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.None, completed: 0)
  let count = row.value.outcome.outcomeContext.value.effectStorageFactCount
  if count.error == AccumulationEffectError.StorageWriteFactsDisabled:
    return AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.StorageFactsDisabled)
  if count.error != AccumulationEffectError.None:
    return AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.InvalidOutcome)
  AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.None, completed: count.value)

proc annulmentSelectedStorageFactAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex, fact: AccumulationStorageFactIndex): AccumulationAnnulmentResult[
        AccumulationStorageFact] =
  ## No original fact may escape through an annulled selection; default/disabled/bounds failures remain distinct.
  let count = plan.annulmentSelectedStorageFactCountAt(index)
  if count.error != AccumulationAnnulmentError.None:
    return AccumulationAnnulmentResult[AccumulationStorageFact](status: count.error)
  if uint64(fact) >= uint64(count.value):
    return AccumulationAnnulmentResult[AccumulationStorageFact](
        status: AccumulationAnnulmentError.InvalidIndex)
  let row = selectedRow(plan, index).value
  AccumulationAnnulmentResult[AccumulationStorageFact](status: AccumulationAnnulmentError.None,
      completed: row.outcome.outcomeContext.value.effectStorageFactAt(fact).value)

proc annulmentSelectedRequestFactCountAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex): AccumulationAnnulmentResult[int] =
  ## Cancelled invocations have a proven empty selected request trace; survivors require enabled original identity capture.
  let row = selectedRow(plan, index)
  if row.error != AccumulationAnnulmentError.None:
    return AccumulationAnnulmentResult[int](status: row.error)
  if row.value.decision.annulled:
    return AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.None, completed: 0)
  let count = row.value.outcome.outcomeContext.value.effectRequestFactCount
  if count.error == AccumulationEffectError.RequestFactsDisabled:
    return AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.RequestFactsDisabled)
  if count.error != AccumulationEffectError.None:
    return AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.InvalidOutcome)
  AccumulationAnnulmentResult[int](status: AccumulationAnnulmentError.None, completed: count.value)
proc annulmentSelectedRequestFactAt*(plan: PreparedAccumulationAnnulment,
    index: AccumulationAnnulmentIndex, fact: AccumulationRequestFactIndex): AccumulationAnnulmentResult[
        AccumulationRequestFact] =
  ## Never export an original request identity through its cancelled selection; validate full ordinals before extraction.
  let count = plan.annulmentSelectedRequestFactCountAt(index)
  if count.error != AccumulationAnnulmentError.None:
    return AccumulationAnnulmentResult[AccumulationRequestFact](status: count.error)
  if uint64(fact) >= uint64(count.value):
    return AccumulationAnnulmentResult[AccumulationRequestFact](
        status: AccumulationAnnulmentError.InvalidIndex)
  let row = selectedRow(plan, index).value
  AccumulationAnnulmentResult[AccumulationRequestFact](status: AccumulationAnnulmentError.None,
      completed: row.outcome.outcomeContext.value.effectRequestFactAt(fact).value)
