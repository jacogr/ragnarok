# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current accpar global role merge and original queue/staging producer choice after conflict annulment.
## Immutable source/privilege certificates do not publish chapters or impersonate completed batch coverage.
import ../codec/[bounded, state_accounts, state_layout, state_trie, state_privileges, natural]
import ./[accumulation_annulment, accumulation_outcome, accumulation_effects, accumulation_context, store]

type
  AccumulationGlobalRoleLimits* = object ## Chain/profile shape and all local inspection/copy policies are explicit.
    privileges*: PrivilegeConfig ## Authoritative core profile plus prior/selected allowance and per-component wire ceilings.
    outcomes*, checks*: ElementLimit ## Every original producer and every source/role predicate consumes work.
    totalBytes*: ByteLimit ## Aggregate original plus merged canonical C(12) bytes, not a single-component alias.
  AccumulationGlobalRoleInfo* = object ## Copied counts do not expose source arrays or imply state publication.
    outcomes*, cores*, always*, encodedBytes*: int ## Actual source traversal, core positions, merged allowances and final wire extent.
    checks*, totalBytes*: uint64 ## Actual charged predicate work and original-plus-output canonical bytes.
  AccumulationGlobalRoleError* {.pure.} = enum ## Refused/default alternatives carry no source, privilege snapshot or entry bytes.
    Uninitialized, None, InvalidSource, InvalidState, InvalidConfig, MalformedState,
    SourceMismatch, LimitExceeded, InvalidIndex, NoOutcome
  GlobalRolesData = ref object # Fixed original-owner indices and immutable snapshots form an acyclic source graph.
    source: PreparedAccumulationAnnulment
    roles: PrivilegeSnapshot
    entry: StateEntry
    manager, delegator, registrar: int
    assigners: seq[int]
    info: AccumulationGlobalRoleInfo
  PreparedAccumulationGlobalRoles* = object ## Only checked current-role preparation constructs a retained selected certificate.
    data: nil GlobalRolesData
  AccumulationGlobalRoleResult*[T] = object ## Read-only tags and success-only guarded extraction prevent forged or partial payloads.
    case status: AccumulationGlobalRoleError
    of None:
      completed: T # No public tag or inactive payload storage.
    else:
      discard      # Failure retains the typed reason alone.

func error*[T](outcome: AccumulationGlobalRoleResult[T]): AccumulationGlobalRoleError =
  ## Inspect the reason without granting result mutation.
  outcome.status
func value*[T](outcome: AccumulationGlobalRoleResult[T]): T {.inline,
    requires: outcome.status == AccumulationGlobalRoleError.None.} =
  ## Extract only complete selected success under checked optimized contracts.
  outcome.completed
func codecError(reason: PrivilegeError): AccumulationGlobalRoleError =
  ## Preserve caller-policy refusal separately from malformed complete source state.
  if reason in {PrivilegeError.LimitExceeded, PrivilegeError.LengthOverflow}:
    return AccumulationGlobalRoleError.LimitExceeded # Never repair or truncate a bounded dictionary.
  if reason == PrivilegeError.InvalidConfig:
    return AccumulationGlobalRoleError.InvalidConfig # Caller chain dimensions remain an explicit authority.
  AccumulationGlobalRoleError.MalformedState
func chooseRole(original, manager, owner: ServiceIndex): ServiceIndex =
  ## Exact accpar R: original owner's handoff survives only when the manager left that role unchanged.
  if uint32(manager) == uint32(original): owner
  else: manager # A changed original-manager choice wins independent of outcome order.
proc findProducer(source: PreparedAccumulationAnnulment, service: ServiceIndex,
    work: var uint64, ceiling: ElementLimit): AccumulationGlobalRoleResult[int] =
  ## Search only genuine unique original producers; canceled/missing owners become prior identity.
  for index in 0..<source.annulmentInfo.value.outcomes:
    if work >= uint64(ceiling):
      return AccumulationGlobalRoleResult[int](status: AccumulationGlobalRoleError.LimitExceeded) # Charge before inspecting the next identity.
    inc work
    let decision = source.annulmentDecisionAt(AccumulationAnnulmentIndex(uint64(index))).value
    if uint32(decision.service) == uint32(service):
      return AccumulationGlobalRoleResult[int](status: AccumulationGlobalRoleError.None,
        completed: (if decision.annulled: -1 else: index)) # N contributes no selected global producer.
  AccumulationGlobalRoleResult[int](status: AccumulationGlobalRoleError.None, completed: -1)
proc selectedPrivileges(source: PreparedAccumulationAnnulment, index: int,
    prior: PrivilegeSnapshot): PrivilegeSnapshot =
  ## Private validated producer indices choose actual selected roles; identity never fabricates a context.
  if index < 0: return prior # Missing/annulled and unavailable-code producers leave global roles unchanged.
  source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(
      index))).value.outcomeContext.value.effectPrivileges.value

proc prepareAccumulationGlobalRoles*(source: PreparedAccumulationAnnulment,
    limits: AccumulationGlobalRoleLimits): AccumulationGlobalRoleResult[
        PreparedAccumulationGlobalRoles] =
  ## Bind merged role values and original authority sources without copying queue/staging payloads or publishing state.
  template fail(reason: AccumulationGlobalRoleError) =
    return AccumulationGlobalRoleResult[PreparedAccumulationGlobalRoles](status: reason)
  let facts = source.annulmentInfo
  if facts.error != AccumulationAnnulmentError.None:
    fail(AccumulationGlobalRoleError.InvalidSource) # No caller-authored cancellation flags or substitute prior.
  if uint64(facts.value.outcomes) > uint64(limits.outcomes):
    fail(AccumulationGlobalRoleError.LimitExceeded) # Bound complete original inspection before state lookup.
  var work = 0'u64
  template spend() =
    if work >= uint64(limits.checks): fail(AccumulationGlobalRoleError.LimitExceeded)
    inc work # Every metadata, source-ID and R predicate is charged before use.
  spend()
  let raw = source.annulmentPrior.value.lookup(chapterKey(StateChapter(12)))
  if raw.error != StateStoreError.None:
    fail(AccumulationGlobalRoleError.InvalidState) # Missing C(12) is never an empty role dictionary.
  let priorBytes = uint64(raw.value.byteLength)
  if priorBytes > uint64(limits.totalBytes):
    fail(AccumulationGlobalRoleError.LimitExceeded) # Charge aggregate prior bytes before codec allocation.
  let decoded = decodePrivilegeState(raw.value.bytes, limits.privileges)
  if decoded.error != PrivilegeError.None: fail(codecError(
      decoded.error)) # Preserve codec policy/config/malformed distinctions.
  if decoded.value.consumed != raw.value.byteLength:
    fail(AccumulationGlobalRoleError.MalformedState) # A prefix cannot authorize an alternate complete C(12) interpretation.
  let prior = decoded.value.snapshot
  let original = prior.privilegeInfo.value
  let cores = original.cores
  if cores > high(int) div sizeof(int) or cores > high(int) div sizeof(ServiceIndex):
    fail(AccumulationGlobalRoleError.LimitExceeded) # Prove per-core descriptor extents before capture.
  for index in 0..<facts.value.outcomes:
    let context = source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(
        index))).value.outcomeContext.value
    spend()
    let initial = context.effectInitialContext.value.contextPrivileges.value.privilegeInfo.value
    if initial.cores != cores or context.effectPrivileges.value.privilegeInfo.value.cores != cores:
      fail(AccumulationGlobalRoleError.SourceMismatch) # Source host profiles cannot reinterpret the original chain's core shape.
  let managerIndex = findProducer(source, original.manager, work, limits.checks)
  if managerIndex.error != AccumulationGlobalRoleError.None: fail(
      managerIndex.error) # No partial owner selection.
  let delegatorIndex = findProducer(source, original.delegator, work, limits.checks)
  if delegatorIndex.error != AccumulationGlobalRoleError.None: fail(
      delegatorIndex.error) # Preserve bounded original delegation lookup.
  let registrarIndex = findProducer(source, original.registrar, work, limits.checks)
  if registrarIndex.error != AccumulationGlobalRoleError.None: fail(
      registrarIndex.error) # Preserve bounded original registrar lookup.
  let manager = selectedPrivileges(source, managerIndex.value, prior)
  let managerInfo = manager.privilegeInfo.value
  let delegator = selectedPrivileges(source, delegatorIndex.value, prior).privilegeInfo.value
  let registrar = selectedPrivileges(source, registrarIndex.value, prior).privilegeInfo.value
  let always = managerInfo.always
  if uint64(always) > uint64(limits.privileges.maxAlways) or always > high(int) div sizeof(AlwaysAccumulate):
    fail(AccumulationGlobalRoleError.LimitExceeded) # Bound selected manager dictionary before copying any entry.
  let prefix = int(natural.encode(JamNatural(always)).len)
  if cores > (high(int)-12-prefix) div 4:
    fail(AccumulationGlobalRoleError.LimitExceeded) # Prove fixed role/core bytes before multiplication.
  let fixed = 12+4*cores+prefix
  if always > (high(int)-fixed) div 12:
    fail(AccumulationGlobalRoleError.LimitExceeded) # Prove complete selected dictionary wire extent.
  let outputBytes = fixed+12*always
  if uint64(outputBytes) > uint64(limits.privileges.maxBytes) or uint64(outputBytes) > uint64(
      limits.totalBytes)-priorBytes:
    fail(AccumulationGlobalRoleError.LimitExceeded) # The original and final complete components consume distinct aggregate bytes.
  spend()
  let nextDelegator = chooseRole(original.delegator, managerInfo.delegator, delegator.delegator)
  spend()
  let nextRegistrar = chooseRole(original.registrar, managerInfo.registrar, registrar.registrar)
  var roles = PrivilegeState(manager: managerInfo.manager, delegator: nextDelegator,
    registrar: nextRegistrar, assigners: newSeq[ServiceIndex](cores), always: newSeq[
        AlwaysAccumulate](always))
  var assigners = newSeq[int](cores)
  for core in 0..<cores:
    let ordinal = PrivilegeCoreIndex(uint64(core))
    let owner = prior.privilegeAssignerAt(ordinal).value
    let selected = findProducer(source, owner, work, limits.checks)
    if selected.error != AccumulationGlobalRoleError.None: fail(
        selected.error) # Do not expose an earlier core's source index.
    assigners[core] = selected.value
    let ownerRoles = selectedPrivileges(source, selected.value, prior)
    spend()
    roles.assigners[core] = chooseRole(owner, manager.privilegeAssignerAt(ordinal).value,
      ownerRoles.privilegeAssignerAt(ordinal).value) # Queue producer remains the original owner even after a role handoff.
  for index in 0..<always:
    roles.always[index] = manager.alwaysAccumulateAt(PrivilegeEntryIndex(uint64(
        index))).value # Preserve canonical numeric keys, zero gas and full unsigned gas.
  let encoded = privilegeStateEntry(roles, limits.privileges)
  if encoded.error != PrivilegeError.None: fail(codecError(
      encoded.error)) # No malformed/oversized candidate bytes escape.
  let captured = decodePrivilegeState(encoded.value.value, limits.privileges)
  if captured.error != PrivilegeError.None: fail(codecError(
      captured.error)) # Public immutable snapshots remain codec-owned.
  if captured.value.consumed != encoded.value.value.len:
    fail(AccumulationGlobalRoleError.InvalidSource) # Require complete canonical round-trip shape before retaining an owner.
  AccumulationGlobalRoleResult[PreparedAccumulationGlobalRoles](
    status: AccumulationGlobalRoleError.None,
    completed: PreparedAccumulationGlobalRoles(data: GlobalRolesData(source: source,
      roles: captured.value.snapshot, entry: encoded.value, manager: managerIndex.value,
      delegator: delegatorIndex.value, registrar: registrarIndex.value, assigners: assigners,
      info: AccumulationGlobalRoleInfo(outcomes: facts.value.outcomes, cores: cores,
        always: always, encodedBytes: outputBytes, checks: work, totalBytes: priorBytes+uint64(
            outputBytes)))))

proc globalRolesInfo*(plan: PreparedAccumulationGlobalRoles): AccumulationGlobalRoleResult[
    AccumulationGlobalRoleInfo] =
  ## Copy bounded selected counts without exposing owner indices or dictionaries.
  let data = plan.data
  if data == nil: return AccumulationGlobalRoleResult[AccumulationGlobalRoleInfo](
      status: AccumulationGlobalRoleError.Uninitialized) # No default role projection.
  AccumulationGlobalRoleResult[AccumulationGlobalRoleInfo](status: AccumulationGlobalRoleError.None,
      completed: data.info)
proc globalRolesSource*(plan: PreparedAccumulationGlobalRoles): AccumulationGlobalRoleResult[
    PreparedAccumulationAnnulment] =
  ## Retain the exact genuine conflict certificate behind all authority choices.
  let data = plan.data
  if data == nil: return AccumulationGlobalRoleResult[PreparedAccumulationAnnulment](
      status: AccumulationGlobalRoleError.Uninitialized) # No fabricated source.
  AccumulationGlobalRoleResult[PreparedAccumulationAnnulment](
      status: AccumulationGlobalRoleError.None, completed: data.source)
proc globalRolesPrivileges*(plan: PreparedAccumulationGlobalRoles): AccumulationGlobalRoleResult[
    PrivilegeSnapshot] =
  ## Retain immutable merged privileges; callers cannot mutate shared dictionary/assigner storage.
  let data = plan.data
  if data == nil: return AccumulationGlobalRoleResult[PrivilegeSnapshot](
      status: AccumulationGlobalRoleError.Uninitialized) # No default manager or empty allowance set.
  AccumulationGlobalRoleResult[PrivilegeSnapshot](status: AccumulationGlobalRoleError.None,
      completed: data.roles)
proc globalRolesEntry*(plan: PreparedAccumulationGlobalRoles): AccumulationGlobalRoleResult[StateEntry] =
  ## Return fresh canonical C(12) bytes; this never publishes state or exposes the retained byte buffer.
  let data = plan.data
  if data == nil: return AccumulationGlobalRoleResult[StateEntry](
      status: AccumulationGlobalRoleError.Uninitialized) # No false empty privilege entry.
  var entry = StateEntry(key: data.entry.key, value: newSeq[byte](data.entry.value.len))
  for index in 0..<entry.value.len: entry.value[index] = data.entry.value[
      index] # Frozen factory bounds prove both copy extents.
  AccumulationGlobalRoleResult[StateEntry](status: AccumulationGlobalRoleError.None,
      completed: entry)
proc producer(data: GlobalRolesData, index: int): AccumulationGlobalRoleResult[
    AccumulationOutcome] =
  ## Private validated indices retain an actual nonannulled original outcome; negative means prior identity.
  if index < 0: return AccumulationGlobalRoleResult[AccumulationOutcome](
      status: AccumulationGlobalRoleError.NoOutcome) # No fabricated execution for a missing/canceled original owner.
  let original = data.source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(index))).value
  AccumulationGlobalRoleResult[AccumulationOutcome](status: AccumulationGlobalRoleError.None,
      completed: original)
proc globalManagerOutcome*(plan: PreparedAccumulationGlobalRoles): AccumulationGlobalRoleResult[
    AccumulationOutcome] =
  ## Only the original manager's surviving context supplies manager and allowances.
  let data = plan.data
  if data == nil: return AccumulationGlobalRoleResult[AccumulationOutcome](
      status: AccumulationGlobalRoleError.Uninitialized) # No default original manager.
  producer(data, data.manager)
proc globalDelegatorOutcome*(plan: PreparedAccumulationGlobalRoles): AccumulationGlobalRoleResult[
    AccumulationOutcome] =
  ## Original delegator supplies staging, even after the manager selects a new delegate.
  let data = plan.data
  if data == nil: return AccumulationGlobalRoleResult[AccumulationOutcome](
      status: AccumulationGlobalRoleError.Uninitialized) # No default staging source.
  producer(data, data.delegator)
proc globalRegistrarOutcome*(plan: PreparedAccumulationGlobalRoles): AccumulationGlobalRoleResult[
    AccumulationOutcome] =
  ## Retain only the original registrar's surviving role context.
  let data = plan.data
  if data == nil: return AccumulationGlobalRoleResult[AccumulationOutcome](
      status: AccumulationGlobalRoleError.Uninitialized) # No fabricated registrar source.
  producer(data, data.registrar)
proc globalAssignerOutcomeAt*(plan: PreparedAccumulationGlobalRoles,
    core: PrivilegeCoreIndex): AccumulationGlobalRoleResult[AccumulationOutcome] =
  ## Original per-core assigner supplies that queue row; full-width positions refuse before narrowing.
  let data = plan.data
  if data == nil: return AccumulationGlobalRoleResult[AccumulationOutcome](
      status: AccumulationGlobalRoleError.Uninitialized) # No default queue source.
  if uint64(core) >= uint64(data.assigners.len): return AccumulationGlobalRoleResult[
      AccumulationOutcome](
      status: AccumulationGlobalRoleError.InvalidIndex) # Upper bits cannot alias another core.
  producer(data, data.assigners[int(uint64(core))])
