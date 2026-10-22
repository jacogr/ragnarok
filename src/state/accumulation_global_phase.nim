# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Apply selected C12 roles, original-owner C2 queues and C7 staging after private account/provision preparation.
## Genuine annulment sources govern every component; no caller map, role recipient or fabricated empty context substitutes authority.
## This reusable phase trusts explicit coverage/frame configuration; it cannot construct an authenticated Stage owner.
import ../codec/[bounded, assurances, state_authorization, state_privileges, state_safrole, state_layout]
import ./[accumulation_provision_phase, accumulation_account_phase, accumulation_coverage,
  accumulation_annulment, accumulation_global_roles, accumulation_outcome,
  accumulation_effects, store]

type
  AccumulationGlobalPhaseLimits* = object ## Every complete global component has explicit shape/count/byte ceilings; aggregate bytes charge original and output.
    roles*: AccumulationGlobalRoleLimits
    queues*: AuthorizationConfig
    staging*: ValidatorStateConfig
    totalBytes*: ByteLimit
  AccumulationGlobalPhaseInfo* = object ## Fixed complete component observations do not claim final block/history completion.
    cores*, validators*: int
    bytes*: uint64
  AccumulationGlobalPhaseError* {.pure.} = enum ## Refusal exposes no selected prefix or partial private state.
    Uninitialized, None, InvalidSource, InvalidConfig, InvalidState, LimitExceeded,
    RoleFailure, QueueFailure, StagingFailure, StoreFailure
  GlobalPhaseData = ref object # Acyclic immutable phase ownership preserves explicit coverage sources and selected output.
    provisions: PreparedAccumulationProvisionPhase
    roles: PreparedAccumulationGlobalRoles
    snapshot: StateStoreSnapshot
    info: AccumulationGlobalPhaseInfo
  PreparedAccumulationGlobalPhase* = object ## Only complete component selection and private atomic apply constructs this phase.
    data: nil GlobalPhaseData
  AccumulationGlobalPhaseResult*[T] = object ## Private success/failure alternatives enforce actual selected reason extraction.
    case status: AccumulationGlobalPhaseError
    of None:
      completed: T
    of RoleFailure:
      roleReason: AccumulationGlobalRoleError
    of QueueFailure:
      queueReason: AuthorizationError
    of StagingFailure:
      stagingReason: StateComponentError
    of StoreFailure:
      storeReason: StateStoreError
    else:
      discard # Default/preflight refusals retain no successful components.

func error*[T](outcome: AccumulationGlobalPhaseResult[T]): AccumulationGlobalPhaseError =
  ## Inspect only the selected reason without allowing retagging.
  outcome.status
func value*[T](outcome: AccumulationGlobalPhaseResult[T]): T {.inline,
    requires: outcome.status == AccumulationGlobalPhaseError.None.} =
  ## Extract complete immutable ownership only after success.
  outcome.completed
proc prepareAccumulationGlobalPhase*(provisions: PreparedAccumulationProvisionPhase,
    limits: AccumulationGlobalPhaseLimits): AccumulationGlobalPhaseResult[
        PreparedAccumulationGlobalPhase] =
  ## Select roles once, preserve original owner queue/roster authority through handoffs, and apply all three canonical chapters privately.
  template fail(reason: AccumulationGlobalPhaseError) =
    return AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase](status: reason)
  template queueFail(reason: AuthorizationError) =
    return AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase](
        status: AccumulationGlobalPhaseError.QueueFailure, queueReason: reason)
  template stagingFail(reason: StateComponentError) =
    return AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase](
        status: AccumulationGlobalPhaseError.StagingFailure, stagingReason: reason)
  let accounts = provisions.provisionPhaseAccounts
  if accounts.error != AccumulationProvisionPhaseError.None:
    fail(AccumulationGlobalPhaseError.InvalidSource) # A default provision phase grants no complete account/provider chain.
  let coverage = accounts.value.accountPhaseCoverage.value
  let source = coverage.coverageAnnulment.value
  let prior = source.annulmentPrior.value
  if uint64(limits.queues.cores) != uint64(limits.roles.privileges.cores) or
      uint64(limits.staging.cores) != uint64(limits.roles.privileges.cores):
    fail(AccumulationGlobalPhaseError.InvalidConfig) # Independent codec policies must describe one complete profile.
  if uint64(limits.totalBytes) == 0:
    fail(AccumulationGlobalPhaseError.LimitExceeded) # Every valid profile has nonempty complete global chapters.
  var roleLimits = limits.roles
  if uint64(roleLimits.totalBytes) > uint64(limits.totalBytes):
    roleLimits.totalBytes = limits.totalBytes # Bound initial role capture by the aggregate budget before its factory allocates.
  let roles = prepareAccumulationGlobalRoles(source, roleLimits)
  if roles.error != AccumulationGlobalRoleError.None:
    return AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase](
        status: AccumulationGlobalPhaseError.RoleFailure, roleReason: roles.error)
  let cores = roles.value.globalRolesInfo.value.cores
  let rawQueues = prior.lookup(chapterKey(StateChapter(2)))
  let rawStaging = prior.lookup(chapterKey(StateChapter(7)))
  if rawQueues.error != StateStoreError.None or rawStaging.error != StateStoreError.None:
    fail(AccumulationGlobalPhaseError.InvalidState) # Missing prior global components cannot become empty identity inputs.
  if uint64(rawQueues.value.byteLength) > uint64(limits.queues.maxBytes):
    queueFail(AuthorizationError.LimitExceeded) # Enforce per-component copy limits before materializing owned input bytes.
  if uint64(rawStaging.value.byteLength) > uint64(limits.staging.maxBytes):
    stagingFail(StateComponentError.LimitExceeded) # Bound the original roster copy independently of aggregate bytes.
  var bytes = roles.value.globalRolesInfo.value.totalBytes
  template charge(amount: uint64) =
    if bytes > uint64(limits.totalBytes) or amount > uint64(limits.totalBytes)-bytes:
      fail(AccumulationGlobalPhaseError.LimitExceeded)
    bytes += amount # Subtraction proves aggregate addition before copying a component.
  charge(uint64(rawQueues.value.byteLength))
  charge(uint64(rawStaging.value.byteLength))
  charge(uint64(rawQueues.value.byteLength)) # Complete fixed queues have the same exact original/output extent.
  let queues = decodeAuthorization(AuthorizationKind.Queues, rawQueues.value.bytes, limits.queues)
  if queues.error != AuthorizationError.None: queueFail(queues.error)
  if queues.value.consumed != rawQueues.value.byteLength:
    queueFail(AuthorizationError.NonCanonical) # A valid prefix with trailing bytes is not a complete chapter.
  let staging = decodeStateValidators(rawStaging.value.bytes, limits.staging)
  if staging.error != StateComponentError.None: stagingFail(staging.error)
  if staging.value.consumed != rawStaging.value.byteLength:
    stagingFail(StateComponentError.NonCanonical) # Preserve the one complete canonical roster representation.
  if cores > high(int) div sizeof(AuthorizerRow) or cores > high(int) div (80*sizeof(
      AuthorizerHash)):
    fail(AccumulationGlobalPhaseError.LimitExceeded) # Prove fixed queue-row/hash extents separately from codec byte limits.
  var rows = newSeq[AuthorizerRow](cores)
  for core in 0..<cores:
    let owner = roles.value.globalAssignerOutcomeAt(PrivilegeCoreIndex(uint64(core)))
    var selected = queues.value.snapshot
    case owner.error
    of AccumulationGlobalRoleError.None:
      selected = owner.value.outcomeContext.value.effectQueues.value # Source is the original surviving assigner, never a new role recipient.
    of AccumulationGlobalRoleError.NoOutcome:
      discard # Absent/annulled owner preserves the genuine prior row.
    else:
      fail(AccumulationGlobalPhaseError.InvalidSource) # A source invariant failure cannot invent identity authority.
    rows[core] = newSeq[AuthorizerHash](80)
    for index in 0..<80:
      rows[core][index] = selected.authorizerAt(AuthorizationCoreIndex(uint64(core)),
          AuthorizationIndex(uint64(
          index))).value # Exact ordered eighty-hash rows are already context/profile certified.
  var roster = staging.value.value
  let delegator = roles.value.globalDelegatorOutcome
  case delegator.error
  of AccumulationGlobalRoleError.None:
    roster = delegator.value.outcomeContext.value.effectStaging.value # Original delegator supplies the complete selected roster.
  of AccumulationGlobalRoleError.NoOutcome:
    discard # No surviving original producer means prior identity.
  else:
    fail(AccumulationGlobalPhaseError.InvalidSource)
  let validators = roster.validatorCount.value
  let measured = stateValidatorSize(ValidatorCount(uint64(validators)), limits.staging)
  if measured.error != StateComponentError.None: stagingFail(measured.error)
  charge(uint64(measured.value))
  if validators > high(int) div sizeof(StateValidator):
    fail(AccumulationGlobalPhaseError.LimitExceeded) # Bound typed record allocation before copying opaque validator fields.
  var records = newSeq[StateValidator](validators)
  for index in 0..<validators:
    records[index] = roster.validatorAt(StateValidatorIndex(uint64(
        index))).value # Preserve protocol order, repeated records and every opaque byte.
  let queueEntry = authorizationEntry(AuthorizationKind.Queues, rows, limits.queues)
  if queueEntry.error != AuthorizationError.None: queueFail(queueEntry.error)
  let stagingEntry = validatorEntry(ValidatorChapter.Staging, records, limits.staging)
  if stagingEntry.error != StateComponentError.None: stagingFail(stagingEntry.error)
  let roleEntry = roles.value.globalRolesEntry.value
  let forked = forkStateStore(provisions.provisionPhaseSnapshot.value)
  if forked.error != StateStoreError.None:
    return AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase](
        status: AccumulationGlobalPhaseError.StoreFailure, storeReason: forked.error)
  var working = forked.value
  let applied = working.apply([StateWrite(key: roleEntry.key, kind: StateWriteKind.Put,
      value: roleEntry.value),
    StateWrite(key: queueEntry.value.key, kind: StateWriteKind.Put, value: queueEntry.value.value),
    StateWrite(key: stagingEntry.value.key, kind: StateWriteKind.Put,
        value: stagingEntry.value.value)])
  if applied.error != StateStoreError.None:
    return AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase](
        status: AccumulationGlobalPhaseError.StoreFailure, storeReason: applied.error)
  AccumulationGlobalPhaseResult[PreparedAccumulationGlobalPhase](
    status: AccumulationGlobalPhaseError.None,
    completed: PreparedAccumulationGlobalPhase(data: GlobalPhaseData(provisions: provisions,
      roles: roles.value, snapshot: applied.value, info: AccumulationGlobalPhaseInfo(cores: cores,
          validators: validators, bytes: bytes))))

func roleFailure*[T](outcome: AccumulationGlobalPhaseResult[
    T]): AccumulationGlobalRoleError {.inline, requires: outcome.status ==
    AccumulationGlobalPhaseError.RoleFailure.} =
  ## Inspect only the actual selected roleReason refusal.
  outcome.roleReason

func queueFailure*[T](outcome: AccumulationGlobalPhaseResult[T]): AuthorizationError {.inline,
    requires: outcome.status == AccumulationGlobalPhaseError.QueueFailure.} =
  ## Inspect only the actual selected queueReason refusal.
  outcome.queueReason

func stagingFailure*[T](outcome: AccumulationGlobalPhaseResult[T]): StateComponentError {.inline,
    requires: outcome.status == AccumulationGlobalPhaseError.StagingFailure.} =
  ## Inspect only the actual selected stagingReason refusal.
  outcome.stagingReason

func storeFailure*[T](outcome: AccumulationGlobalPhaseResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationGlobalPhaseError.StoreFailure.} =
  ## Inspect only the actual selected storeReason refusal.
  outcome.storeReason

proc globalPhaseInfo*(stage: PreparedAccumulationGlobalPhase): AccumulationGlobalPhaseResult[
    AccumulationGlobalPhaseInfo] =
  ## Retain the complete info owner; a default phase never grants extraction.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalPhaseResult[AccumulationGlobalPhaseInfo](
        status: AccumulationGlobalPhaseError.Uninitialized)
  AccumulationGlobalPhaseResult[AccumulationGlobalPhaseInfo](
      status: AccumulationGlobalPhaseError.None, completed: data.info)

proc globalPhaseProvisions*(stage: PreparedAccumulationGlobalPhase): AccumulationGlobalPhaseResult[
    PreparedAccumulationProvisionPhase] =
  ## Retain the complete provisions owner; a default phase never grants extraction.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalPhaseResult[PreparedAccumulationProvisionPhase](
        status: AccumulationGlobalPhaseError.Uninitialized)
  AccumulationGlobalPhaseResult[PreparedAccumulationProvisionPhase](
      status: AccumulationGlobalPhaseError.None, completed: data.provisions)

proc globalPhaseRoles*(stage: PreparedAccumulationGlobalPhase): AccumulationGlobalPhaseResult[
    PreparedAccumulationGlobalRoles] =
  ## Retain the complete roles owner; a default phase never grants extraction.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalPhaseResult[PreparedAccumulationGlobalRoles](
        status: AccumulationGlobalPhaseError.Uninitialized)
  AccumulationGlobalPhaseResult[PreparedAccumulationGlobalRoles](
      status: AccumulationGlobalPhaseError.None, completed: data.roles)

proc globalPhaseSnapshot*(stage: PreparedAccumulationGlobalPhase): AccumulationGlobalPhaseResult[
    StateStoreSnapshot] =
  ## Retain the complete snapshot owner; a default phase never grants extraction.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalPhaseResult[StateStoreSnapshot](
        status: AccumulationGlobalPhaseError.Uninitialized)
  AccumulationGlobalPhaseResult[StateStoreSnapshot](status: AccumulationGlobalPhaseError.None,
      completed: data.snapshot)
