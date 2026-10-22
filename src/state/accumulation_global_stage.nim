# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Apply selected C12 roles, original-owner C2 queues and C7 staging after private account/provision preparation.
## Genuine annulment sources govern every component; no caller map, role recipient or fabricated empty context substitutes authority.
import ../codec/[bounded, assurances, state_authorization, state_privileges, state_safrole, state_layout]
import ./[accumulation_provision_stage, accumulation_account_stage, accumulation_block_guests,
  accumulation_coverage, accumulation_annulment, accumulation_global_roles, accumulation_outcome,
  accumulation_effects, accumulation_round, accumulation_queue, report_admission, block_transition, store]

type
  AccumulationGlobalStageLimits* = object ## Every complete global component has explicit shape/count/byte ceilings; aggregate bytes charge original and output.
    roles*: AccumulationGlobalRoleLimits
    queues*: AuthorizationConfig
    staging*: ValidatorStateConfig
    totalBytes*: ByteLimit
  AccumulationGlobalStageInfo* = object ## Fixed complete component observations do not claim final block/history completion.
    cores*, validators*: int
    bytes*: uint64
  AccumulationGlobalStageError* {.pure.} = enum ## Refusal exposes no selected prefix or partial private state.
    Uninitialized, None, InvalidSource, InvalidConfig, InvalidState, LimitExceeded,
    RoleFailure, QueueFailure, StagingFailure, StoreFailure
  GlobalStageData = ref object # Acyclic immutable phase ownership preserves authenticated sources and selected output.
    provisions: PreparedAccumulationProvisionStage
    roles: PreparedAccumulationGlobalRoles
    snapshot: StateStoreSnapshot
    info: AccumulationGlobalStageInfo
  PreparedAccumulationGlobalStage* = object ## Only complete component selection and private atomic apply constructs this phase.
    data: nil GlobalStageData
  AccumulationGlobalStageResult*[T] = object ## Private success/failure alternatives enforce actual selected reason extraction.
    case status: AccumulationGlobalStageError
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

func error*[T](outcome: AccumulationGlobalStageResult[T]): AccumulationGlobalStageError =
  ## Inspect only the selected reason without allowing retagging.
  outcome.status
func value*[T](outcome: AccumulationGlobalStageResult[T]): T {.inline,
    requires: outcome.status == AccumulationGlobalStageError.None.} =
  ## Extract complete immutable ownership only after success.
  outcome.completed
proc prepareAccumulationGlobalStage*(provisions: PreparedAccumulationProvisionStage,
    limits: AccumulationGlobalStageLimits): AccumulationGlobalStageResult[
        PreparedAccumulationGlobalStage] =
  ## Select roles once, preserve original owner queue/roster authority through handoffs, and apply all three canonical chapters privately.
  template fail(reason: AccumulationGlobalStageError) =
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](status: reason)
  template queueFail(reason: AuthorizationError) =
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.QueueFailure, queueReason: reason)
  template stagingFail(reason: StateComponentError) =
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.StagingFailure, stagingReason: reason)
  let accounts = provisions.provisionStageAccounts
  if accounts.error != AccumulationProvisionStageError.None:
    fail(AccumulationGlobalStageError.InvalidSource) # No default/pure projection grants a genuine account/provider chain.
  let guests = accounts.value.accountStageGuests.value
  let profile = guests.guestRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.blockTransitionProfile
  let source = guests.guestCoverage.value.coverageAnnulment.value
  let prior = source.annulmentPrior.value
  if uint64(limits.roles.privileges.cores) != uint64(profile.cores) or
      uint64(limits.queues.cores) != uint64(limits.roles.privileges.cores) or
      uint64(limits.staging.cores) != uint64(limits.roles.privileges.cores):
    fail(AccumulationGlobalStageError.InvalidConfig) # Independent codec policies must describe one complete profile.
  if uint64(limits.totalBytes) == 0:
    fail(AccumulationGlobalStageError.LimitExceeded) # Every valid profile has nonempty complete global chapters.
  var roleLimits = limits.roles
  if uint64(roleLimits.totalBytes) > uint64(limits.totalBytes):
    roleLimits.totalBytes = limits.totalBytes # Bound initial role capture by the aggregate budget before its factory allocates.
  let roles = prepareAccumulationGlobalRoles(source, roleLimits)
  if roles.error != AccumulationGlobalRoleError.None:
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.RoleFailure, roleReason: roles.error)
  let cores = roles.value.globalRolesInfo.value.cores
  let rawQueues = prior.lookup(chapterKey(StateChapter(2)))
  let rawStaging = prior.lookup(chapterKey(StateChapter(7)))
  if rawQueues.error != StateStoreError.None or rawStaging.error != StateStoreError.None:
    fail(AccumulationGlobalStageError.InvalidState) # Missing prior global components cannot become empty identity inputs.
  if uint64(rawQueues.value.byteLength) > uint64(limits.queues.maxBytes):
    queueFail(AuthorizationError.LimitExceeded) # Enforce per-component copy limits before materializing owned input bytes.
  if uint64(rawStaging.value.byteLength) > uint64(limits.staging.maxBytes):
    stagingFail(StateComponentError.LimitExceeded) # Bound the original roster copy independently of aggregate bytes.
  var bytes = roles.value.globalRolesInfo.value.totalBytes
  template charge(amount: uint64) =
    if bytes > uint64(limits.totalBytes) or amount > uint64(limits.totalBytes)-bytes:
      fail(AccumulationGlobalStageError.LimitExceeded)
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
    fail(AccumulationGlobalStageError.LimitExceeded) # Prove fixed queue-row/hash extents separately from codec byte limits.
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
      fail(AccumulationGlobalStageError.InvalidSource) # A source invariant failure cannot invent identity authority.
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
    fail(AccumulationGlobalStageError.InvalidSource)
  let validators = roster.validatorCount.value
  let measured = stateValidatorSize(ValidatorCount(uint64(validators)), limits.staging)
  if measured.error != StateComponentError.None: stagingFail(measured.error)
  charge(uint64(measured.value))
  if validators > high(int) div sizeof(StateValidator):
    fail(AccumulationGlobalStageError.LimitExceeded) # Bound typed record allocation before copying opaque validator fields.
  var records = newSeq[StateValidator](validators)
  for index in 0..<validators:
    records[index] = roster.validatorAt(StateValidatorIndex(uint64(
        index))).value # Preserve protocol order, repeated records and every opaque byte.
  let queueEntry = authorizationEntry(AuthorizationKind.Queues, rows, limits.queues)
  if queueEntry.error != AuthorizationError.None: queueFail(queueEntry.error)
  let stagingEntry = validatorEntry(ValidatorChapter.Staging, records, limits.staging)
  if stagingEntry.error != StateComponentError.None: stagingFail(stagingEntry.error)
  let roleEntry = roles.value.globalRolesEntry.value
  let forked = forkStateStore(provisions.provisionStageSnapshot.value)
  if forked.error != StateStoreError.None:
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.StoreFailure, storeReason: forked.error)
  var working = forked.value
  let applied = working.apply([StateWrite(key: roleEntry.key, kind: StateWriteKind.Put,
      value: roleEntry.value),
    StateWrite(key: queueEntry.value.key, kind: StateWriteKind.Put, value: queueEntry.value.value),
    StateWrite(key: stagingEntry.value.key, kind: StateWriteKind.Put,
        value: stagingEntry.value.value)])
  if applied.error != StateStoreError.None:
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
        status: AccumulationGlobalStageError.StoreFailure, storeReason: applied.error)
  AccumulationGlobalStageResult[PreparedAccumulationGlobalStage](
    status: AccumulationGlobalStageError.None,
    completed: PreparedAccumulationGlobalStage(data: GlobalStageData(provisions: provisions,
      roles: roles.value, snapshot: applied.value, info: AccumulationGlobalStageInfo(cores: cores,
          validators: validators, bytes: bytes))))

func roleFailure*[T](outcome: AccumulationGlobalStageResult[
    T]): AccumulationGlobalRoleError {.inline, requires: outcome.status ==
    AccumulationGlobalStageError.RoleFailure.} =
  ## Inspect only the actual selected roleReason refusal.
  outcome.roleReason

func queueFailure*[T](outcome: AccumulationGlobalStageResult[T]): AuthorizationError {.inline,
    requires: outcome.status == AccumulationGlobalStageError.QueueFailure.} =
  ## Inspect only the actual selected queueReason refusal.
  outcome.queueReason

func stagingFailure*[T](outcome: AccumulationGlobalStageResult[T]): StateComponentError {.inline,
    requires: outcome.status == AccumulationGlobalStageError.StagingFailure.} =
  ## Inspect only the actual selected stagingReason refusal.
  outcome.stagingReason

func storeFailure*[T](outcome: AccumulationGlobalStageResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationGlobalStageError.StoreFailure.} =
  ## Inspect only the actual selected storeReason refusal.
  outcome.storeReason

proc globalStageInfo*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    AccumulationGlobalStageInfo] =
  ## Retain the complete info owner; a default phase never grants extraction.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[AccumulationGlobalStageInfo](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[AccumulationGlobalStageInfo](
      status: AccumulationGlobalStageError.None, completed: data.info)

proc globalStageProvisions*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    PreparedAccumulationProvisionStage] =
  ## Retain the complete provisions owner; a default phase never grants extraction.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[PreparedAccumulationProvisionStage](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[PreparedAccumulationProvisionStage](
      status: AccumulationGlobalStageError.None, completed: data.provisions)

proc globalStageRoles*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    PreparedAccumulationGlobalRoles] =
  ## Retain the complete roles owner; a default phase never grants extraction.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[PreparedAccumulationGlobalRoles](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[PreparedAccumulationGlobalRoles](
      status: AccumulationGlobalStageError.None, completed: data.roles)

proc globalStageSnapshot*(stage: PreparedAccumulationGlobalStage): AccumulationGlobalStageResult[
    StateStoreSnapshot] =
  ## Retain the complete snapshot owner; a default phase never grants extraction.
  let data = stage.data
  if data == nil:
    return AccumulationGlobalStageResult[StateStoreSnapshot](
        status: AccumulationGlobalStageError.Uninitialized)
  AccumulationGlobalStageResult[StateStoreSnapshot](status: AccumulationGlobalStageError.None,
      completed: data.snapshot)
