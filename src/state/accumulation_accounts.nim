# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Update existing accumulated accounts' timestamps on a private finalized map using genuine statistics and block time.
## Pure projections return caller-owned writes; only statistics-bound preparation creates the immutable successor certificate.

import ../codec/[bounded, composite, header, state_accounts, state_layout, state_trie, state_statistics]
import ./[accumulation_statistics, accumulation_finalization, accumulation_outputs,
  accumulation_execution, accumulation_round, accumulation_queue, report_admission,
  block_transition, block_admission, store]

type
  AccumulationAccountConfig* = object ## Traversal and aggregate selected existing metadata bytes have independent local ceilings.
    services*: ElementLimit
    metadataBytes*: ByteLimit
  AccumulationAccountInfo* = object ## Copied observations distinguish statistics keys, existing accounts and actual changed timestamps.
    slot*: AccountSlot
    services*, accounts*, updates*: int
  AccumulationAccountProjection* = object ## Caller-owned pure writes are not a source-bound execution or state-publication certificate.
    info*: AccumulationAccountInfo
    writes*: seq[StateWrite]
  AccumulationAccountError* {.pure.} = enum ## Defaults/refusals expose no partial projection, source or successor state.
    Uninitialized,   ## Default result or prepared account owner.
    None,            ## Complete selected success permits extraction.
    InvalidSource,   ## No genuine finalized statistics mapping was supplied.
    InvalidState,    ## No initialized complete map or exact fixed selected metadata record.
    InvalidServices, ## Projection identities are not numeric sorted and unique.
    LimitExceeded,   ## Service traversal, metadata capture or native allocation exceeds policy.
    MetadataFailure, ## Inspect the selected canonical metadata decoder reason.
    StateFailure     ## Inspect the actual private store/backend refusal.
  # Immutable acyclic ownership binds the exact statistics/finalization graph to its private complete-map successor.
  AccountData = ref object
    source: PreparedAccumulationStatistics
    state: StateStoreSnapshot
    info: AccumulationAccountInfo
  PreparedAccumulationAccounts* = object ## Only genuine finalized statistics authorizes this private account-timestamp successor.
    data: nil AccountData
  AccumulationAccountResult*[T] = object ## Failed alternatives retain their reason alone or the selected nested failure.
    case status: AccumulationAccountError
    of None:
      completed: T # Success extraction stays guarded in checked optimized builds.
    of MetadataFailure:
      metadataReason: ServiceMetadataError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # No fabricated empty state or earlier successful projection survives a refusal.

func error*[T](outcome: AccumulationAccountResult[T]): AccumulationAccountError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: AccumulationAccountResult[T]): T {.inline,
    requires: outcome.status == AccumulationAccountError.None.} =
  ## Extract only selected complete success.
  outcome.completed
func metadataError*[T](outcome: AccumulationAccountResult[T]): ServiceMetadataError {.inline,
    requires: outcome.status == AccumulationAccountError.MetadataFailure.} =
  ## Inspect only an actual selected metadata decoder failure.
  outcome.metadataReason
func stateError*[T](outcome: AccumulationAccountResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationAccountError.StateFailure.} =
  ## Inspect only an actual private store refusal.
  outcome.stateReason

proc projectAccumulationAccounts*(prior: StateStoreSnapshot, services: openArray[ServiceIndex],
    slot: AccountSlot, config: AccumulationAccountConfig): AccumulationAccountResult[
        AccumulationAccountProjection] =
  ## Borrow stable canonical identities, copy exact existing metadata and return independent writes without hashing.
  ## Missing accounts stay absent; existing accounts already at the selected slot need no write.
  template fail(reason: AccumulationAccountError) =
    return AccumulationAccountResult[AccumulationAccountProjection](status: reason)
  if forkStateStore(prior).error != StateStoreError.None:
    fail(AccumulationAccountError.InvalidState) # A default map cannot masquerade as initialized empty state.
  if uint64(services.len) > uint64(config.services) or services.len > high(int) div sizeof(StateWrite):
    fail(AccumulationAccountError.LimitExceeded) # Bound all lookup work and candidate descriptors before allocation.
  var accounts = 0
  var bytes = 0'u64
  for index, service in services:
    if index > 0 and uint32(services[index-1]) >= uint32(service):
      fail(AccumulationAccountError.InvalidServices) # Require numeric uniqueness/order before emitting any writes.
    let found = prior.lookup(chapterServiceKey(StateChapter(255), service))
    if found.error != StateStoreError.MissingKey:
      if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
        fail(AccumulationAccountError.InvalidState) # Exact fixed extent precedes copying or decoding metadata.
      if uint64(ServiceMetadataBytes) > uint64(config.metadataBytes)-bytes:
        fail(AccumulationAccountError.LimitExceeded) # Count all inspected existing records, including unchanged timestamps.
      bytes += uint64(ServiceMetadataBytes)
      inc accounts # Existing accounts are a subset of the already bounded service identities.
  var writes = newSeq[StateWrite](services.len)
  var updates = 0
  for service in services:
    let found = prior.lookup(chapterServiceKey(StateChapter(255), service))
    if found.error == StateStoreError.None:
      let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
      if decoded.error != ServiceMetadataError.None:
        return AccumulationAccountResult[AccumulationAccountProjection](
          status: AccumulationAccountError.MetadataFailure,
          metadataReason: decoded.error) # No earlier candidate escapes malformed selected metadata.
      var metadata = decoded.value.metadata
      if uint32(metadata.lastAccumulation) != uint32(slot):
        metadata.lastAccumulation = slot # Preserve every other fixed field from the actual posterior account.
        let entry = serviceMetadataEntry(service, metadata, ByteLimit(ServiceMetadataBytes)).value
        writes[updates] = StateWrite(key: entry.key, kind: StateWriteKind.Put, value: entry.value)
        inc updates # At most one distinct write per checked service.
  var retained = newSeq[StateWrite](updates)
  for index in 0..<updates:
    retained[index] = writes[index] # Return only the initialized candidate prefix with independent metadata bytes.
  AccumulationAccountResult[AccumulationAccountProjection](status: AccumulationAccountError.None,
    completed: AccumulationAccountProjection(info: AccumulationAccountInfo(slot: slot,
      services: services.len, accounts: accounts, updates: updates), writes: retained))

proc accumulationAccountInfo*(plan: PreparedAccumulationAccounts): AccumulationAccountResult[
    AccumulationAccountInfo] =
  ## Copy counts and authenticated slot without exposing private storage.
  let data = plan.data
  if data == nil:
    return AccumulationAccountResult[AccumulationAccountInfo](
        status: AccumulationAccountError.Uninitialized) # Defaults have no observed progress.
  AccumulationAccountResult[AccumulationAccountInfo](status: AccumulationAccountError.None,
      completed: data.info)
proc accumulationAccountSource*(plan: PreparedAccumulationAccounts): AccumulationAccountResult[
    PreparedAccumulationStatistics] =
  ## Retain the exact statistics and original finalization independently of the caller's source handles.
  let data = plan.data
  if data == nil:
    return AccumulationAccountResult[PreparedAccumulationStatistics](
        status: AccumulationAccountError.Uninitialized) # No synthesized statistics owner.
  AccumulationAccountResult[PreparedAccumulationStatistics](status: AccumulationAccountError.None,
      completed: data.source)
proc accumulationAccountState*(plan: PreparedAccumulationAccounts): AccumulationAccountResult[
    StateStoreSnapshot] =
  ## Retain the complete private successor under the source store's inherited policy.
  let data = plan.data
  if data == nil:
    return AccumulationAccountResult[StateStoreSnapshot](
        status: AccumulationAccountError.Uninitialized) # No partial map from refused preparation.
  AccumulationAccountResult[StateStoreSnapshot](status: AccumulationAccountError.None,
      completed: data.state)

proc prepareAccumulationAccounts*(source: PreparedAccumulationStatistics,
    config: AccumulationAccountConfig): AccumulationAccountResult[PreparedAccumulationAccounts] =
  ## Derive state, canonical keys and child slot only from genuine finalized statistics; apply privately and atomically.
  let facts = source.statisticsInfo
  if facts.error != AccumulationStatisticsError.None:
    return AccumulationAccountResult[PreparedAccumulationAccounts](
        status: AccumulationAccountError.InvalidSource) # Raw mappings/finalizations cannot replace statistics provenance.
  let count = facts.value.services
  if uint64(count) > uint64(config.services) or count > high(int) div sizeof(ServiceIndex):
    return AccumulationAccountResult[PreparedAccumulationAccounts](
        status: AccumulationAccountError.LimitExceeded) # Bound source extraction before allocating service descriptors.
  var services = newSeq[ServiceIndex](count)
  for index in 0..<count:
    services[index] = source.statisticsAt(StatisticsServiceIndex(uint64(
        index))).value.service # Numeric order and nonzero activity are certified by statistics.
  let finalized = source.statisticsSource.value
  let initial = finalized.finalAccumulationOutputs.value.outputsSource.value
  let admitted = initial.executionRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted
  let slot = AccountSlot(uint32(headerInfo(admitted.admittedHeader).value.unsigned.slot))
  let prior = finalized.finalAccumulationState.value
  let projected = projectAccumulationAccounts(prior, services, slot, config)
  if projected.error == AccumulationAccountError.MetadataFailure:
    return AccumulationAccountResult[PreparedAccumulationAccounts](
        status: AccumulationAccountError.MetadataFailure, metadataReason: projected.metadataError)
  if projected.error != AccumulationAccountError.None:
    return AccumulationAccountResult[PreparedAccumulationAccounts](
        status: projected.error) # No projected payload survives failure.
  var working = forkStateStore(prior).value
  let applied = working.apply(projected.value.writes)
  if applied.error != StateStoreError.None:
    return AccumulationAccountResult[PreparedAccumulationAccounts](
      status: AccumulationAccountError.StateFailure,
      stateReason: applied.error) # Backend/policy refusal leaves all retained sources unchanged.
  AccumulationAccountResult[PreparedAccumulationAccounts](status: AccumulationAccountError.None,
    completed: PreparedAccumulationAccounts(data: AccountData(source: source,
      state: applied.value, info: projected.value.info)))
