# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind original pools, posterior queues and verified guarantee use to one authenticated accumulation successor.
## Only a private complete-map C(1) replacement is prepared; whole-block publication remains separate.

import ../codec/bounded as codec_bounded
import ../codec/assurances as codec_assurances
import ../codec/header as codec_header
import ../codec/report_owned as codec_report_owned
import ../codec/state_authorization as codec_state_authorization
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ./accumulation_authorization as state_accumulation_authorization
import ./accumulation_current_preimages as state_accumulation_current_preimages
import ./accumulation_current_activity as state_accumulation_current_activity
import ./accumulation_current_validators as state_accumulation_current_validators
import ./accumulation_current_recent as state_accumulation_current_recent
import ./accumulation_current_ready as state_accumulation_current_ready
import ./accumulation_current_finalization as state_accumulation_current_finalization
import ./accumulation_current_accounts as state_accumulation_current_accounts
import ./accumulation_current_statistics as state_accumulation_current_statistics
import ./accumulation_current_driver as state_accumulation_current_driver
import ./accumulation_current_sequence as state_accumulation_current_sequence
import ./accumulation_current_round as state_accumulation_current_round
import ./accumulation_block_guests as state_accumulation_block_guests
import ./accumulation_round as state_accumulation_round
import ./accumulation_queue as state_accumulation_queue
import ./report_admission as state_report_admission
import ./guarantee_credentials as state_guarantee_credentials
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./authorization as state_authorization
import ./store as state_store

type
  CurrentAccumulationAuthorizationError* {.pure.} = enum ## Failed/default alternatives retain neither a partial entry nor a usable successor.
    Uninitialized, None, InvalidSource, LimitExceeded, CodecFailure, AuthorizationFailure, StateFailure
  # Acyclic immutable owner retains exact source authority and the new private complete-map state.
  CurrentAuthorizationData = ref object
    source: PreparedCurrentAccumulationPreimages
    info: AccumulationAuthorizationInfo
    entry: StateEntry
    state: StateStoreSnapshot
  PreparedCurrentAccumulationAuthorization* = object ## Only the source-derived constructor can authorize this private C(1) successor.
    data: nil CurrentAuthorizationData
  CurrentAccumulationAuthorizationResult*[T] = object ## Only selected success carries values; child causes have separate guarded alternatives.
    case status: CurrentAccumulationAuthorizationError
    of None:
      completed: T
    of CodecFailure:
      codecReason: AuthorizationError
    of AuthorizationFailure:
      authorizationReason: AuthorizationTransitionError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard # Early/default failures contain reasons alone.

func error*[T](outcome: CurrentAccumulationAuthorizationResult[
    T]): CurrentAccumulationAuthorizationError =
  ## Inspect the selected reason without writable tags.
  outcome.status
func value*[T](outcome: CurrentAccumulationAuthorizationResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationAuthorizationError.None.} =
  ## Extract only selected complete success under optimized checked contracts.
  outcome.completed
func codecError*[T](outcome: CurrentAccumulationAuthorizationResult[
    T]): AuthorizationError {.inline,

requires: outcome.status == CurrentAccumulationAuthorizationError.CodecFailure.} =
  ## Inspect only an actual chapter decoding refusal.
  outcome.codecReason
func authorizationError*[T](outcome: CurrentAccumulationAuthorizationResult[
    T]): AuthorizationTransitionError {.inline,

requires: outcome.status == CurrentAccumulationAuthorizationError.AuthorizationFailure.} =
  ## Inspect only the pure pool transition refusal.
  outcome.authorizationReason
func stateError*[T](outcome: CurrentAccumulationAuthorizationResult[T]): StateStoreError {.inline,
    requires: outcome.status == CurrentAccumulationAuthorizationError.StateFailure.} =
  ## Inspect only a complete-map lookup or atomic publication refusal.
  outcome.stateReason

proc currentAuthorizationSource*(plan: PreparedCurrentAccumulationAuthorization):
    CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationPreimages] =
  ## Retain the exact lookup candidate and its original-parent/body authority.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationPreimages](
      status: CurrentAccumulationAuthorizationError.Uninitialized) # Defaults have no authenticated source.
  CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationPreimages](
    status: CurrentAccumulationAuthorizationError.None, completed: data.source)

proc currentAuthorizationInfo*(plan: PreparedCurrentAccumulationAuthorization):
    CurrentAccumulationAuthorizationResult[AccumulationAuthorizationInfo] =
  ## Copy fixed observations without granting a mutable row or domain override.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationAuthorizationResult[AccumulationAuthorizationInfo](
      status: CurrentAccumulationAuthorizationError.Uninitialized) # No fabricated empty observations.
  CurrentAccumulationAuthorizationResult[AccumulationAuthorizationInfo](
    status: CurrentAccumulationAuthorizationError.None, completed: data.info)

proc currentAuthorizationEntry*(plan: PreparedCurrentAccumulationAuthorization):
    CurrentAccumulationAuthorizationResult[StateEntry] =
  ## Copy every encoded octet so callers cannot mutate the retained entry or published snapshot.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationAuthorizationResult[StateEntry](
      status: CurrentAccumulationAuthorizationError.Uninitialized) # Defaults expose no partial encoding.
  var bytes = newSeq[byte](data.entry.value.len)
  for index in 0..<bytes.len: bytes[index] = data.entry.value[index] # Independent extraction owns its storage.
  CurrentAccumulationAuthorizationResult[StateEntry](
    status: CurrentAccumulationAuthorizationError.None,
    completed: StateEntry(key: data.entry.key, value: bytes))

proc currentAuthorizationState*(plan: PreparedCurrentAccumulationAuthorization):
    CurrentAccumulationAuthorizationResult[StateStoreSnapshot] =
  ## Retain the complete private successor after exactly one C(1) replacement.
  let data = plan.data
  if data == nil:
    return CurrentAccumulationAuthorizationResult[StateStoreSnapshot](
      status: CurrentAccumulationAuthorizationError.Uninitialized) # No default root or partial map escapes.
  CurrentAccumulationAuthorizationResult[StateStoreSnapshot](
    status: CurrentAccumulationAuthorizationError.None, completed: data.state)

proc prepareCurrentAccumulationAuthorization*(source: PreparedCurrentAccumulationPreimages,
    limits: AccumulationAuthorizationLimits):
    CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization] =
  ## Derive verified incoming uses and exact original/posterior component roles, then atomically fork C(1).
  template fail(reason: CurrentAccumulationAuthorizationError) =
    return CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization](status: reason)
  let retained = source.currentPreimagesSource
  if retained.error != CurrentAccumulationPreimageError.None:
    fail(CurrentAccumulationAuthorizationError.InvalidSource) # Default owners cannot stand for initialized empty blocks.
  let finalized = retained.value.currentActivitySource.value.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value
  let completed = finalized.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let admission = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value
  let stage = admission.reportBlockStage.value
  let binding = stage.value.admitted
  let cores = stage.blockTransitionProfile.cores
  let slot = binding.admittedHeader.headerInfo.value.unsigned.slot
  let credentials = admission.reportCredentials.value
  let count = credentials.verifiedGuaranteeCount.value
  if uint64(count) > uint64(limits.guarantees): fail(
      CurrentAccumulationAuthorizationError.LimitExceeded)
  if count > high(int) div sizeof(CoreAuthorizer): fail(
      CurrentAccumulationAuthorizationError.LimitExceeded)
  let prior = source.currentPreimagesState.value
  let poolBytes = binding.admittedState.lookup(chapterKey(StateChapter(1)))
  let queueBytes = prior.lookup(chapterKey(StateChapter(2)))
  for reason in [poolBytes.error, queueBytes.error]:
    if reason != StateStoreError.None:
      return CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization](
        status: CurrentAccumulationAuthorizationError.StateFailure,
        stateReason: reason) # Missing chapters cannot be inferred or substituted from another phase.
  if uint64(poolBytes.value.byteLength) > uint64(limits.inputBytes): fail(
      CurrentAccumulationAuthorizationError.LimitExceeded)
  if uint64(queueBytes.value.byteLength) > uint64(limits.inputBytes): fail(
      CurrentAccumulationAuthorizationError.LimitExceeded)
  let codec = AuthorizationConfig(cores: cores, maxHashes: limits.inputHashes,
      maxBytes: limits.inputBytes)
  let pools = decodeAuthorization(AuthorizationKind.Pools, poolBytes.value.bytes, codec)
  let queues = decodeAuthorization(AuthorizationKind.Queues, queueBytes.value.bytes, codec)
  for reason in [pools.error, queues.error]:
    if reason != AuthorizationError.None:
      return CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization](
        status: CurrentAccumulationAuthorizationError.CodecFailure,
        codecReason: reason) # Bounded exact input decoding never repairs malformed state.
  if pools.value.consumed != poolBytes.value.byteLength or queues.value.consumed !=
      queueBytes.value.byteLength:
    return CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization](
      status: CurrentAccumulationAuthorizationError.CodecFailure,
      codecReason: AuthorizationError.NonCanonical) # Canonical chapter values cannot carry a suffix.
  var uses = newSeq[CoreAuthorizer](count)
  for index in 0..<count:
    let report = credentials.verifiedGuaranteeAt(index).value.report.ownedReportInfo.value
    uses[index] = CoreAuthorizer(core: AuthorizationCoreIndex(uint64(report.core)),
      authorizer: report.authorizer) # Exact incoming verified reports alone consume authorizers.
  let projected = advanceAuthorization(pools.value.snapshot, queues.value.snapshot, uses,
    AuthorizationSlot(uint32(slot)), AuthorizationConfig(cores: cores,
      maxHashes: limits.outputHashes, maxBytes: limits.outputBytes))
  if projected.error != AuthorizationTransitionError.None:
    return CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization](
      status: CurrentAccumulationAuthorizationError.AuthorizationFailure,
      authorizationReason: projected.error) # Pure output refusal precedes every private write.
  var working = forkStateStore(prior).value
  let applied = working.apply([StateWrite(key: projected.value.key, kind: StateWriteKind.Put,
    value: projected.value.value)])
  if applied.error != StateStoreError.None:
    return CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization](
      status: CurrentAccumulationAuthorizationError.StateFailure,
      stateReason: applied.error) # Failed root construction preserves every earlier owner and map.
  CurrentAccumulationAuthorizationResult[PreparedCurrentAccumulationAuthorization](
    status: CurrentAccumulationAuthorizationError.None,
    completed: PreparedCurrentAccumulationAuthorization(data: CurrentAuthorizationData(
      source: source,
      info: AccumulationAuthorizationInfo(slot: slot, cores: cores, guarantees: count,
        encodedBytes: projected.value.value.len), entry: projected.value, state: applied.value)))
