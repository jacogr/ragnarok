# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 partialstate/I: immutable initial regular and exceptional accumulation contexts.
## Exposes bounded chapter binding and retained account/queue/staging/privilege views; no execution or writes.

import ../codec/[bounded, assurances, composite, header, state_layout, state_authorization,
  state_safrole, state_privileges, state_accounts]
import ./[accumulation_invocation, accumulation_service, accumulation_round, accumulation_queue,
  report_admission, block_transition, store]

type
  ## Explicit chain population and independent decoding/aggregate-copy ceilings.
  AccumulationContextConfig* = object
    validators*: ValidatorCount
    queues*: AuthorizationConfig
    staging*: ValidatorStateConfig
    privileges*: PrivilegeConfig
    totalBytes*: ByteLimit
  ## Initial dimensions share I; only a future checkpoint operation may distinguish them.
  AccumulationDimension* {.pure.} = enum
    Regular, Exceptional
  ## Refusal contains no partially decoded state or fabricated implications.
  AccumulationContextError* {.pure.} = enum
    Uninitialized, None, InvalidInvocation, InvalidConfig, MissingState, MalformedState,
    LimitExceeded, InvalidDimension
  ## Copied initial I metadata; effects are empty and yield is absent before any execution.
  InitialAccumulationInfo* = object
    service*, nextService*: ServiceIndex
    transfers*, provisions*: int
    hasYield*: bool
  ## Acyclic private storage retains the exact bootstrap and complete-map account backing.
  ContextData = ref object
    invocation: PreparedAccumulationInvocation
    accounts: StateStoreSnapshot
    queues: AuthorizationSnapshot
    staging: ValidatorStateSnapshot
    privileges: PrivilegeSnapshot
  ## Immutable initial implications; no mutable sequence or checkpoint state is exported.
  InitialAccumulationContext* = object
    data: nil ContextData
  ## Both dimensions initially refer to one immutable I, making initial equality structural.
  PreparedAccumulationContexts* = object
    initial: InitialAccumulationContext
  ## Retained certificate prevents replacement of the block, entropy or parent state.
  BlockContextData = ref object
    invocation: BlockAccumulationInvocation
    projection: PreparedAccumulationContexts
  ## Only the bound adapter constructs contexts tied to an authenticated chain profile.
  BlockAccumulationContexts* = object
    data: nil BlockContextData
  ## Select success before reading any private completed payload, including in optimized builds.
  AccumulationContextResult*[T] = object
    case status: AccumulationContextError
    of None:
      completed: T # Complete initialization alone publishes retained views.
    else:
      discard      # No partially decoded values accompany refusal.

## Read a reason without permitting result retagging.
func error*[T](outcome: AccumulationContextResult[T]): AccumulationContextError = outcome.status
## Extract only explicitly selected success under compiler/runtime contracts.
func value*[T](outcome: AccumulationContextResult[T]): T {.inline,
    requires: outcome.status == AccumulationContextError.None.} = outcome.completed

## Select either initial dimension; reject invalid enum casts instead of aliasing arbitrary dimensions.
proc initialContext*(contexts: PreparedAccumulationContexts,
    dimension: AccumulationDimension): AccumulationContextResult[InitialAccumulationContext] =
  if ord(dimension) < ord(AccumulationDimension.Regular) or
      ord(dimension) > ord(AccumulationDimension.Exceptional):
    return AccumulationContextResult[InitialAccumulationContext](status:
      AccumulationContextError.InvalidDimension) # Unchecked casts must not extend the protocol tuple.
  if contexts.initial.data == nil:
    return AccumulationContextResult[InitialAccumulationContext](status:
      AccumulationContextError.Uninitialized) # Default pairs are not initialized I values.
  AccumulationContextResult[InitialAccumulationContext](status: AccumulationContextError.None,
    completed: contexts.initial)

## Copy I's service/next-ID and its genuinely empty initial effects, without claiming an outcome.
proc contextInfo*(context: InitialAccumulationContext): AccumulationContextResult[
    InitialAccumulationInfo] =
  let data = context.data
  if data == nil: return AccumulationContextResult[InitialAccumulationInfo](status:
    AccumulationContextError.Uninitialized) # No synthetic service or effects.
  let seed = data.invocation.bootstrapInfo.value
  AccumulationContextResult[InitialAccumulationInfo](status: AccumulationContextError.None,
    completed: InitialAccumulationInfo(service: seed.service, nextService: seed.nextService,
      transfers: 0, provisions: 0, hasYield: false))

## Retain the exact bootstrap, including immutable input provenance and independent argument extraction.
proc contextInvocation*(context: InitialAccumulationContext): AccumulationContextResult[
    PreparedAccumulationInvocation] =
  let data = context.data
  if data == nil: return AccumulationContextResult[PreparedAccumulationInvocation](status:
    AccumulationContextError.Uninitialized) # No default bootstrap masquerades as initialized.
  AccumulationContextResult[PreparedAccumulationInvocation](status: AccumulationContextError.None,
    completed: data.invocation)

## Retain the complete source map backing all service accounts/storage/preimages, without computing a partial root.
## Other chapters remain present; this view neither filters the map nor validates every unrelated account value.
proc contextAccounts*(context: InitialAccumulationContext): AccumulationContextResult[
    StateStoreSnapshot] =
  let data = context.data
  if data == nil: return AccumulationContextResult[StateStoreSnapshot](status:
    AccumulationContextError.Uninitialized) # No empty-map substitution.
  AccumulationContextResult[StateStoreSnapshot](status: AccumulationContextError.None,
    completed: data.accounts)

## Extract the invoking account already validated by the retained service preparation.
proc contextSelf*(context: InitialAccumulationContext): AccumulationContextResult[ServiceMetadata] =
  let data = context.data
  if data == nil: return AccumulationContextResult[ServiceMetadata](status:
    AccumulationContextError.Uninitialized) # No default account on failed setup.
  AccumulationContextResult[ServiceMetadata](status: AccumulationContextError.None,
    completed: data.invocation.bootstrapService.value.serviceInfo.value.account)

## Retain the decoded C(2) queue owner; bounded per-core extraction never exports mutable rows.
proc contextQueues*(context: InitialAccumulationContext): AccumulationContextResult[
    AuthorizationSnapshot] =
  let data = context.data
  if data == nil: return AccumulationContextResult[AuthorizationSnapshot](status:
    AccumulationContextError.Uninitialized) # No fabricated empty queues.
  AccumulationContextResult[AuthorizationSnapshot](status: AccumulationContextError.None,
    completed: data.queues)

## Retain C(7)'s ordered staging roster; active/previous rosters are not substitutes.
proc contextStaging*(context: InitialAccumulationContext): AccumulationContextResult[
    ValidatorStateSnapshot] =
  let data = context.data
  if data == nil: return AccumulationContextResult[ValidatorStateSnapshot](status:
    AccumulationContextError.Uninitialized) # No fabricated empty roster.
  AccumulationContextResult[ValidatorStateSnapshot](status: AccumulationContextError.None,
    completed: data.staging)

## Retain all C(12) roles, assigners and always-accumulate allowances without mutable aliases.
proc contextPrivileges*(context: InitialAccumulationContext): AccumulationContextResult[
    PrivilegeSnapshot] =
  let data = context.data
  if data == nil: return AccumulationContextResult[PrivilegeSnapshot](status:
    AccumulationContextError.Uninitialized) # No synthetic privilege roles.
  AccumulationContextResult[PrivilegeSnapshot](status: AccumulationContextError.None,
    completed: data.privileges)

## Bind exact bootstrap state and complete partialstate components; pure callers supply the chain profile.
## Each chapter is length-preflighted before copying; aggregate arithmetic uses subtraction before addition.
proc prepareAccumulationContexts*(invocation: PreparedAccumulationInvocation,
    config: AccumulationContextConfig): AccumulationContextResult[PreparedAccumulationContexts] =
  ## Refuse atomically; earlier decoded components remain local and are released on failure.
  template fail(reason: AccumulationContextError) =
    return AccumulationContextResult[PreparedAccumulationContexts](status: reason)
  let cores = uint64(config.queues.cores)
  let population = uint64(config.validators)
  if cores < 2 or cores > 341 or uint64(config.staging.cores) != cores or
      uint64(config.privileges.cores) != cores or population < 6 or population mod 3 != 0 or
      population div 3 > cores:
    fail(AccumulationContextError.InvalidConfig) # Match the supported coherent chain cardinalities before decoding.
  let service = invocation.bootstrapService
  if service.error != AccumulationInvocationError.None:
    fail(AccumulationContextError.InvalidInvocation) # Only successful ready-code bootstraps initialize I.
  let state = service.value.serviceState.value
  var values = default(array[3, StateValue])
  var total = 0'u64
  let ceilings = [config.queues.maxBytes, config.staging.maxBytes, config.privileges.maxBytes]
  # Locate every mandatory component and prove all copy extents before allocating chapter buffers.
  for i, chapter in [2, 7, 12]:
    let found = state.lookup(chapterKey(StateChapter(chapter)))
    if found.error == StateStoreError.MissingKey:
      fail(AccumulationContextError.MissingState) # Never replace missing queue/staging/privileges with defaults.
    if found.error != StateStoreError.None:
      fail(AccumulationContextError.InvalidInvocation) # Retained valid bootstrap state cannot be replaced.
    let bytes = uint64(found.value.byteLength)
    if bytes > uint64(ceilings[i]) or bytes > uint64(config.totalBytes)-total:
      fail(AccumulationContextError.LimitExceeded) # Includes trailing bytes, even if a prefix decoder would stop earlier.
    total += bytes
    values[i] = found.value
  let queues = decodeAuthorization(AuthorizationKind.Queues, values[0].bytes, config.queues)
  if queues.error == AuthorizationError.LimitExceeded or queues.error ==
      AuthorizationError.LengthOverflow:
    fail(AccumulationContextError.LimitExceeded) # Resource refusals are not malformed-state claims.
  if queues.error != AuthorizationError.None:
    fail(AccumulationContextError.MalformedState) # Reject incomplete or invalid fixed queue shapes.
  if queues.value.consumed != values[0].byteLength:
    fail(AccumulationContextError.MalformedState) # Require the entire C(2), not a valid prefix with suffix garbage.
  let staging = decodeStateValidators(values[1].bytes, config.staging)
  if staging.error == StateComponentError.LimitExceeded or staging.error ==
      StateComponentError.LengthOverflow:
    fail(AccumulationContextError.LimitExceeded) # Preserve caller ceilings separately from protocol shape.
  if staging.error != StateComponentError.None:
    fail(AccumulationContextError.MalformedState) # No malformed roster owner escapes.
  if staging.value.consumed != values[1].byteLength or uint64(
      staging.value.value.validatorCount.value) != population:
    fail(AccumulationContextError.MalformedState) # A structurally valid different chain population still mismatches.
  let privileges = decodePrivilegeState(values[2].bytes, config.privileges)
  if privileges.error == PrivilegeError.LimitExceeded or privileges.error ==
      PrivilegeError.LengthOverflow:
    fail(AccumulationContextError.LimitExceeded) # No partial roles on dictionary/byte exhaustion.
  if privileges.error != PrivilegeError.None:
    fail(AccumulationContextError.MalformedState) # Invalid ordering/framing cannot define initial privileges.
  if privileges.value.consumed != values[2].byteLength:
    fail(AccumulationContextError.MalformedState) # No suffix tolerance at whole-state boundaries.
  let initial = InitialAccumulationContext(data: ContextData(invocation: invocation,
    accounts: state,
    queues: queues.value.snapshot, staging: staging.value.value,
    privileges: privileges.value.snapshot))
  AccumulationContextResult[PreparedAccumulationContexts](status: AccumulationContextError.None,
    completed: PreparedAccumulationContexts(initial: initial))

## Retain the genuine source certificate independently of the paired-context handle.
proc contextBlockInvocation*(contexts: BlockAccumulationContexts): AccumulationContextResult[
    BlockAccumulationInvocation] =
  let data = contexts.data
  if data == nil: return AccumulationContextResult[BlockAccumulationInvocation](status:
    AccumulationContextError.Uninitialized) # No forged block provenance.
  AccumulationContextResult[BlockAccumulationInvocation](status: AccumulationContextError.None,
    completed: data.invocation)

## Retain the complete immutable initial pair from a genuine block-bound preparation.
proc contextProjection*(contexts: BlockAccumulationContexts): AccumulationContextResult[
    PreparedAccumulationContexts] =
  let data = contexts.data
  if data == nil: return AccumulationContextResult[PreparedAccumulationContexts](status:
    AccumulationContextError.Uninitialized) # No fabricated initial contexts.
  AccumulationContextResult[PreparedAccumulationContexts](status: AccumulationContextError.None,
    completed: data.projection)

## Bind cardinalities to this invocation's certified block profile; state comes only from its service owner.
proc prepareBlockAccumulationContexts*(invocation: BlockAccumulationInvocation,
    config: AccumulationContextConfig): AccumulationContextResult[BlockAccumulationContexts] =
  ## Refuse without publishing a partially bound context certificate.
  template fail(reason: AccumulationContextError) =
    return AccumulationContextResult[BlockAccumulationContexts](status: reason)
  let source = invocation.bootstrapBlockService
  if source.error != AccumulationInvocationError.None:
    fail(AccumulationContextError.InvalidInvocation) # Default block bootstraps do not authorize initialization.
  let stage = source.value.serviceBlockRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  if uint64(config.queues.cores) != uint64(profile.cores) or
      uint64(config.validators) != uint64(profile.validators):
    fail(AccumulationContextError.InvalidConfig) # The supplied decoding policy cannot substitute another chain population.
  let prepared = prepareAccumulationContexts(invocation.bootstrapProjection.value, config)
  if prepared.error != AccumulationContextError.None: fail(prepared.error) # Preserve complete pure refusal.
  AccumulationContextResult[BlockAccumulationContexts](status: AccumulationContextError.None,
    completed: BlockAccumulationContexts(data: BlockContextData(invocation: invocation,
      projection: prepared.value)))
