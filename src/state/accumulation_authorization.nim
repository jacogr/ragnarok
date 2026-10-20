# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind original pools, posterior queues and verified guarantee use to one authenticated accumulation successor.
## Only a private complete-map C(1) replacement is prepared; whole-block publication remains separate.

import ../codec/[bounded, assurances, header, report_owned, state_authorization, state_layout, state_trie]
import ./[accumulation_preimages, accumulation_activity, accumulation_validators,
  accumulation_times,
  accumulation_statistics, accumulation_finalization, accumulation_outputs, accumulation_execution,
  accumulation_round, accumulation_queue, report_admission, guarantee_credentials, block_transition,
  block_admission, authorization, store]

type
  AccumulationAuthorizationLimits* = object ## Resource policies cannot replace source-derived chain domains or guarantee use.
    guarantees*: ElementLimit   ## Maximum verified incoming guarantee descriptors copied.
    inputHashes*: ElementLimit  ## Per original-pool/posterior-queue hash population before retention.
    inputBytes*: ByteLimit      ## Per exact input chapter before copying and decoding.
    outputHashes*: ElementLimit ## Maximum projected pool hash population across all cores.
    outputBytes*: ByteLimit     ## Complete canonical C(1) encoding, including pool count prefixes.
  AccumulationAuthorizationInfo* = object ## Copied observations never expose source rows or mutable encoding storage.
    slot*: HeaderSlot  ## Exact authenticated block time used for cyclic queue indexing.
    cores*: CoreCount  ## Core population derived from the same block's frame profile.
    guarantees*: int   ## Incoming verified guarantee uses, excluding newly available reports.
    encodedBytes*: int ## Complete retained C(1) entry extent.
  AccumulationAuthorizationError* {.pure.} = enum ## Failed/default alternatives retain neither a partial entry nor a usable successor.
    Uninitialized, None, InvalidSource, LimitExceeded, CodecFailure, AuthorizationFailure, StateFailure
  # Acyclic immutable owner retains exact source authority and the new private complete-map state.
  AccumulationAuthorizationData = ref object
    source: PreparedAccumulationPreimages
    info: AccumulationAuthorizationInfo
    entry: StateEntry
    state: StateStoreSnapshot
  PreparedAccumulationAuthorization* = object ## Only the source-derived constructor can authorize this private C(1) successor.
    data: nil AccumulationAuthorizationData
  AccumulationAuthorizationResult*[T] = object ## Only selected success carries values; child causes have separate guarded alternatives.
    case status: AccumulationAuthorizationError
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

func error*[T](outcome: AccumulationAuthorizationResult[T]): AccumulationAuthorizationError =
  ## Inspect the selected reason without writable tags.
  outcome.status
func value*[T](outcome: AccumulationAuthorizationResult[T]): T {.inline,
    requires: outcome.status == AccumulationAuthorizationError.None.} =
  ## Extract only selected complete success under optimized checked contracts.
  outcome.completed
func codecError*[T](outcome: AccumulationAuthorizationResult[T]): AuthorizationError {.inline,
    requires: outcome.status == AccumulationAuthorizationError.CodecFailure.} =
  ## Inspect only an actual chapter decoding refusal.
  outcome.codecReason
func authorizationError*[T](outcome: AccumulationAuthorizationResult[
    T]): AuthorizationTransitionError {.inline,

requires: outcome.status == AccumulationAuthorizationError.AuthorizationFailure.} =
  ## Inspect only the pure pool transition refusal.
  outcome.authorizationReason
func stateError*[T](outcome: AccumulationAuthorizationResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationAuthorizationError.StateFailure.} =
  ## Inspect only a complete-map lookup or atomic publication refusal.
  outcome.stateReason

proc accumulationAuthorizationSource*(plan: PreparedAccumulationAuthorization):
    AccumulationAuthorizationResult[PreparedAccumulationPreimages] =
  ## Retain the exact lookup candidate and its original-parent/body authority.
  let data = plan.data
  if data == nil:
    return AccumulationAuthorizationResult[PreparedAccumulationPreimages](
      status: AccumulationAuthorizationError.Uninitialized) # Defaults have no authenticated source.
  AccumulationAuthorizationResult[PreparedAccumulationPreimages](
    status: AccumulationAuthorizationError.None, completed: data.source)

proc accumulationAuthorizationInfo*(plan: PreparedAccumulationAuthorization):
    AccumulationAuthorizationResult[AccumulationAuthorizationInfo] =
  ## Copy fixed observations without granting a mutable row or domain override.
  let data = plan.data
  if data == nil:
    return AccumulationAuthorizationResult[AccumulationAuthorizationInfo](
      status: AccumulationAuthorizationError.Uninitialized) # No fabricated empty observations.
  AccumulationAuthorizationResult[AccumulationAuthorizationInfo](
    status: AccumulationAuthorizationError.None, completed: data.info)

proc accumulationAuthorizationEntry*(plan: PreparedAccumulationAuthorization):
    AccumulationAuthorizationResult[StateEntry] =
  ## Copy every encoded octet so callers cannot mutate the retained entry or published snapshot.
  let data = plan.data
  if data == nil:
    return AccumulationAuthorizationResult[StateEntry](
      status: AccumulationAuthorizationError.Uninitialized) # Defaults expose no partial encoding.
  var bytes = newSeq[byte](data.entry.value.len)
  for index in 0..<bytes.len: bytes[index] = data.entry.value[index] # Independent extraction owns its storage.
  AccumulationAuthorizationResult[StateEntry](status: AccumulationAuthorizationError.None,
    completed: StateEntry(key: data.entry.key, value: bytes))

proc accumulationAuthorizationState*(plan: PreparedAccumulationAuthorization):
    AccumulationAuthorizationResult[StateStoreSnapshot] =
  ## Retain the complete private successor after exactly one C(1) replacement.
  let data = plan.data
  if data == nil:
    return AccumulationAuthorizationResult[StateStoreSnapshot](
      status: AccumulationAuthorizationError.Uninitialized) # No default root or partial map escapes.
  AccumulationAuthorizationResult[StateStoreSnapshot](
    status: AccumulationAuthorizationError.None, completed: data.state)

proc prepareAccumulationAuthorization*(source: PreparedAccumulationPreimages,
    limits: AccumulationAuthorizationLimits):
    AccumulationAuthorizationResult[PreparedAccumulationAuthorization] =
  ## Derive verified incoming uses and exact original/posterior component roles, then atomically fork C(1).
  template fail(reason: AccumulationAuthorizationError) =
    return AccumulationAuthorizationResult[PreparedAccumulationAuthorization](status: reason)
  let retained = source.accumulationPreimagesSource
  if retained.error != AccumulationPreimageError.None:
    fail(AccumulationAuthorizationError.InvalidSource) # Default owners cannot stand for initialized empty blocks.
  let finalized = retained.value.accumulationActivitySource.value.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  let admission = finalized.finalAccumulationOutputs.value.outputsSource.value.executionRound.value.roundBlockQueue.value.accumulationAdmission.value
  let stage = admission.reportBlockStage.value
  let binding = stage.value.admitted
  let cores = stage.blockTransitionProfile.cores
  let slot = binding.admittedHeader.headerInfo.value.unsigned.slot
  let credentials = admission.reportCredentials.value
  let count = credentials.verifiedGuaranteeCount.value
  if uint64(count) > uint64(limits.guarantees): fail(AccumulationAuthorizationError.LimitExceeded)
  if count > high(int) div sizeof(CoreAuthorizer): fail(
      AccumulationAuthorizationError.LimitExceeded)
  let prior = source.accumulationPreimagesState.value
  let poolBytes = binding.admittedState.lookup(chapterKey(StateChapter(1)))
  let queueBytes = prior.lookup(chapterKey(StateChapter(2)))
  for reason in [poolBytes.error, queueBytes.error]:
    if reason != StateStoreError.None:
      return AccumulationAuthorizationResult[PreparedAccumulationAuthorization](
        status: AccumulationAuthorizationError.StateFailure,
        stateReason: reason) # Missing chapters cannot be inferred or substituted from another phase.
  if uint64(poolBytes.value.byteLength) > uint64(limits.inputBytes): fail(
      AccumulationAuthorizationError.LimitExceeded)
  if uint64(queueBytes.value.byteLength) > uint64(limits.inputBytes): fail(
      AccumulationAuthorizationError.LimitExceeded)
  let codec = AuthorizationConfig(cores: cores, maxHashes: limits.inputHashes,
      maxBytes: limits.inputBytes)
  let pools = decodeAuthorization(AuthorizationKind.Pools, poolBytes.value.bytes, codec)
  let queues = decodeAuthorization(AuthorizationKind.Queues, queueBytes.value.bytes, codec)
  for reason in [pools.error, queues.error]:
    if reason != AuthorizationError.None:
      return AccumulationAuthorizationResult[PreparedAccumulationAuthorization](
        status: AccumulationAuthorizationError.CodecFailure,
        codecReason: reason) # Bounded exact input decoding never repairs malformed state.
  if pools.value.consumed != poolBytes.value.byteLength or queues.value.consumed !=
      queueBytes.value.byteLength:
    return AccumulationAuthorizationResult[PreparedAccumulationAuthorization](
      status: AccumulationAuthorizationError.CodecFailure,
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
    return AccumulationAuthorizationResult[PreparedAccumulationAuthorization](
      status: AccumulationAuthorizationError.AuthorizationFailure,
      authorizationReason: projected.error) # Pure output refusal precedes every private write.
  var working = forkStateStore(prior).value
  let applied = working.apply([StateWrite(key: projected.value.key, kind: StateWriteKind.Put,
    value: projected.value.value)])
  if applied.error != StateStoreError.None:
    return AccumulationAuthorizationResult[PreparedAccumulationAuthorization](
      status: AccumulationAuthorizationError.StateFailure,
      stateReason: applied.error) # Failed root construction preserves every earlier owner and map.
  AccumulationAuthorizationResult[PreparedAccumulationAuthorization](
    status: AccumulationAuthorizationError.None,
    completed: PreparedAccumulationAuthorization(data: AccumulationAuthorizationData(source: source,
      info: AccumulationAuthorizationInfo(slot: slot, cores: cores, guarantees: count,
        encodedBytes: projected.value.value.len), entry: projected.value, state: applied.value)))
