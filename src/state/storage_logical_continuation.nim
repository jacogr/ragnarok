# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reconstruct complete current logical state across only producer-proven storage identity changes, retaining original parent and genuine successor provenance.
import ./[parent_logical, current_logical, current_identities, accumulation_current_update,
    accumulation_storage_history, accumulation_effects, supplied_logical_inventory,
    supplied_services, inventory, store, current_profile, current_globals, current_state, global_snapshot]
import ../codec/[bounded, state_layout, state_composition, state_accounts, state_requests]
type
  StorageContinuationLimits* = object ## Original binding, admitted identity scratch, bounded planning and whole output/current qualification retain independent policies.
    identity*: CurrentIdentityLimits
    checks*: ElementLimit
    scratchBytes*: ByteLimit
    projection*: SuppliedServicesLimits
    profile*: CurrentProfileLimits
    globals*: GlobalStateLimits
    logical*: SuppliedLogicalLimits
  StorageContinuationError* {.pure.} = enum ## Unsupported namespaces, missing producer capture, exact source and genuine typed qualification refusal expose no prefix.
    Uninitialized, None, InvalidParent, IdentityFailure, MissingStorageEvidence, LimitExceeded,
    UnsupportedChange, MetadataFailure, RequestFailure, ProfileFailure, GlobalsFailure,
    StateFailure, LogicalFailure
  StorageContinuationResult* = object ## Only complete original-current and raw-key requalification exposes a logical successor.
    case status: StorageContinuationError
    of None: completed: CurrentLogicalState
    of IdentityFailure: identityReason: CurrentIdentityResult[PreservedCurrentIdentities]
    of MetadataFailure: metadataReason: ServiceMetadataError
    of RequestFailure: requestReason: RequestError
    of ProfileFailure: profileReason: CurrentProfileResult[DerivedCurrentProfile]
    of GlobalsFailure: globalsReason: CurrentGlobalsResult[CurrentGlobalSerialization]
    of StateFailure: stateReason: CurrentStateResult[CurrentStateSerialization]
    of LogicalFailure: logicalReason: CurrentLogicalResult[CurrentLogicalState]
    else: discard # No candidate service declarations or successful earlier certificate escapes.
  StorageIdentityRow = object ## Admitted private scratch owns raw identities; presence and evidence remain bound to this exact target.
    owner: int
    key: StateKey
    raw: seq[byte]
    present, original, produced: bool
func error*(outcome: StorageContinuationResult): StorageContinuationError =
  ## Observe the immutable selected continuation stage.
  outcome.status
func value*(outcome: StorageContinuationResult): CurrentLogicalState {.inline,
    requires: outcome.status == StorageContinuationError.None.} =
  ## Complete original current qualification alone grants a retained logical successor.
  outcome.completed
func identityFailure*(outcome: StorageContinuationResult): CurrentIdentityResult[
    PreservedCurrentIdentities] {.inline, requires: outcome.status ==
    StorageContinuationError.IdentityFailure.} =
  ## Preserve actual original state/view/Parameters/resource refusal; accepted identity changes never appear as a failed source prefix.
  outcome.identityReason
func metadataError*(outcome: StorageContinuationResult): ServiceMetadataError {.inline,
    requires: outcome.status == StorageContinuationError.MetadataFailure.} =
  ## Preserve exact current metadata decoding refusal.
  outcome.metadataReason
func requestError*(outcome: StorageContinuationResult): RequestError {.inline,
    requires: outcome.status == StorageContinuationError.RequestFailure.} =
  ## Preserve actual request key or history decoding refusal.
  outcome.requestReason
func profileFailure*(outcome: StorageContinuationResult): CurrentProfileResult[
    DerivedCurrentProfile] {.inline, requires: outcome.status ==
    StorageContinuationError.ProfileFailure.} =
  ## Preserve independently bounded original-current profile qualification refusal.
  outcome.profileReason
func globalsFailure*(outcome: StorageContinuationResult): CurrentGlobalsResult[
    CurrentGlobalSerialization] {.inline, requires: outcome.status ==
    StorageContinuationError.GlobalsFailure.} =
  ## Preserve exact all-global decoding refusal on the original successor.
  outcome.globalsReason
func stateFailure*(outcome: StorageContinuationResult): CurrentStateResult[
    CurrentStateSerialization] {.inline, requires: outcome.status ==
    StorageContinuationError.StateFailure.} =
  ## Preserve complete actual-map mismatch, including unsupported added namespaces.
  outcome.stateReason
func logicalFailure*(outcome: StorageContinuationResult): CurrentLogicalResult[
    CurrentLogicalState] {.inline, requires: outcome.status ==
    StorageContinuationError.LogicalFailure.} =
  ## Preserve late raw-key/current-bound capture refusal without successful prefix authority.
  outcome.logicalReason
proc continueStorage(original: SuppliedLogicalInventory,
    binding: CurrentIdentityResult[PreservedCurrentIdentities], update: PreparedCurrentChainUpdate,
    limits: StorageContinuationLimits): StorageContinuationResult =
  ## Accept strict identity-set refusal only after that API has validated every original parent/view/full-Parameters boundary; reconcile storage from this update's own producer evidence.
  template fail(reason: StorageContinuationError) =
    return StorageContinuationResult(status: reason)
  if binding.error notin {CurrentIdentityError.None, CurrentIdentityError.NewIdentity,
      CurrentIdentityError.MissingIdentity}:
    return StorageContinuationResult(status: StorageContinuationError.IdentityFailure,
        identityReason: binding)
  if not update.hasStorageHistory: fail(StorageContinuationError.MissingStorageEvidence)
  let history = update.currentUpdateStorageHistory
  let produced = history.storageHistoryInfo.value
  let compact = original.suppliedInventory.value
  let info = compact.inventoryInfo.value
  let raw = original.suppliedLogicalInfo.value
  let target = update.currentUpdateState
  if uint64(info.services) > uint64(limits.projection.services): fail(
      StorageContinuationError.LimitExceeded)
  var scratch = min(uint64(limits.scratchBytes), uint64(high(int)))
  let slots = scratch div uint64(sizeof(StorageIdentityRow))
  if raw.keys > slots or uint64(produced.facts) > slots-raw.keys: fail(
      StorageContinuationError.LimitExceeded)
  let capacity = raw.keys+uint64(produced.facts)
  scratch -= capacity*uint64(sizeof(StorageIdentityRow))
  if info.facts > scratch div uint64(sizeof(StateKey)): fail(StorageContinuationError.LimitExceeded)
  scratch -= info.facts*uint64(sizeof(StateKey))
  if raw.rawKeyBytes > scratch: fail(StorageContinuationError.LimitExceeded)
  scratch -= raw.rawKeyBytes
  if uint64(produced.facts) > produced.bytes div uint64(sizeof(StorageHistoryRow)):
    fail(StorageContinuationError.LimitExceeded) # Prove descriptor multiplication against the immutable captured byte ledger.
  let descriptors = uint64(produced.facts)*uint64(sizeof(StorageHistoryRow))
  if descriptors > produced.bytes or produced.bytes-descriptors > scratch:
    fail(StorageContinuationError.LimitExceeded) # All possible raw copies, identity rows and request-key scratch fit before allocation.
  var rows = newSeq[StorageIdentityRow](int(capacity))
  var requestKeys = newSeq[StateKey](int(info.facts))
  var used = 0
  var work = uint64(limits.checks)
  template spend() =
    if work == 0: fail(StorageContinuationError.LimitExceeded)
    dec work
  for i in 0..<info.services:
    spend()
    let service = InventoryServiceIndex(uint64(i))
    let row = compact.inventoryServiceAt(service).value
    for j in 0..<row.storage:
      spend()
      let index = InventoryStorageIndex(uint64(j))
      let fact = compact.inventoryStorageAt(service, index).value
      if fact.keyBytes > uint64(limits.projection.perValue): fail(
          StorageContinuationError.LimitExceeded)
      let found = target.lookup(fact.key)
      if found.error notin {StateStoreError.None, StateStoreError.MissingKey}: fail(
          StorageContinuationError.UnsupportedChange)
      rows[used] = StorageIdentityRow(owner: i, key: fact.key,
          raw: original.copySuppliedStorageKey(service, index, limits.projection.perValue).value,
          present: found.error == StateStoreError.None, original: true, produced: false)
      inc used # Original qualified counts fit the admitted fixed identity scratch.
  for i in 0..<produced.facts:
    spend()
    let fact = history.storageHistoryAt(StorageHistoryIndex(uint64(i))).value.fact
    let details = fact.storageFactInfo.value
    if uint64(details.rawBytes) > uint64(limits.projection.perValue): fail(
        StorageContinuationError.LimitExceeded)
    var owner = -1
    for j in 0..<info.services:
      spend()
      if uint32(compact.inventoryServiceAt(InventoryServiceIndex(uint64(j))).value.service) ==
          uint32(details.service): owner = j
    if owner < 0: fail(StorageContinuationError.UnsupportedChange) # Service creation/deletion needs its own producer contract.
    let key = fact.copyStorageFactKey(limits.projection.perValue).value
    var selected = -1
    for j in 0..<used:
      spend()
      if rows[j].owner == owner and array[31, byte](rows[j].key) == array[31, byte](
          details.key): selected = j
    if selected >= 0:
      if rows[selected].raw != key: fail(StorageContinuationError.UnsupportedChange) # Physical equality cannot replace exact original raw identity.
      rows[selected].produced = true
    else:
      let found = target.lookup(details.key)
      if found.error notin {StateStoreError.None, StateStoreError.MissingKey}: fail(
          StorageContinuationError.UnsupportedChange)
      rows[used] = StorageIdentityRow(owner: owner, key: details.key, raw: key,
          present: found.error == StateStoreError.None, original: false, produced: true)
      inc used # Multiple selected invocations coalesce only identical raw storage identities.
  var bytes = min(uint64(limits.projection.bytes), uint64(high(int)))
  var facts = uint64(limits.projection.facts)
  template charge(count: int, kind: untyped) =
    block:
      let extent = uint64(count)
      if extent > facts or extent > bytes div uint64(sizeof(kind)): fail(
          StorageContinuationError.LimitExceeded)
      facts -= extent
      bytes -= extent*uint64(sizeof(kind))
  template payload(size: uint64) =
    block:
      let extent = size
      if extent > uint64(limits.projection.perValue) or extent > bytes: fail(
          StorageContinuationError.LimitExceeded)
      bytes -= extent
  charge(info.services, StateService)
  var requestCount = 0
  for i in 0..<info.services:
    spend()
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = compact.inventoryServiceAt(ordinal).value
    let metadata = target.lookup(chapterServiceKey(StateChapter(255), row.service))
    if metadata.error != StateStoreError.None: fail(StorageContinuationError.UnsupportedChange)
    if metadata.value.byteLength != ServiceMetadataBytes: fail(
        StorageContinuationError.UnsupportedChange)
    payload(uint64(ServiceMetadataBytes)) # Actual codec wires have explicit temporary copy admission too.
    var storage = 0
    for j in 0..<used:
      spend()
      if rows[j].owner == i:
        if rows[j].original and not rows[j].present and not rows[j].produced:
          fail(StorageContinuationError.UnsupportedChange) # No deletion is inferred from an unexplained map difference.
        if rows[j].present:
          inc storage
          payload(uint64(rows[j].raw.len))
          payload(uint64(target.lookup(rows[j].key).value.byteLength))
    charge(storage, StateStorageItem)
    charge(row.preimages, StatePreimageItem)
    charge(row.requests, StateRequestItem)
    for j in 0..<row.preimages:
      spend()
      let fact = compact.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value
      let value = target.lookup(fact.key)
      if value.error != StateStoreError.None: fail(StorageContinuationError.UnsupportedChange)
      payload(uint64(value.value.byteLength))
    for j in 0..<row.requests:
      spend()
      let fact = compact.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
      let key = serviceRequestKey(row.service, fact.hash, fact.length, ByteLimit(32))
      if key.error != RequestError.None:
        return StorageContinuationResult(status: StorageContinuationError.RequestFailure,
            requestReason: key.error)
      requestKeys[requestCount] = key.value
      inc requestCount # Original compact fact count bounds this admitted request-key array.
      let value = target.lookup(key.value)
      if value.error != StateStoreError.None: fail(StorageContinuationError.UnsupportedChange)
      if value.value.byteLength > 13: fail(StorageContinuationError.UnsupportedChange)
      payload(uint64(value.value.byteLength))
  var services = newSeq[StateService](info.services)
  requestCount = 0
  for i in 0..<info.services:
    # Every output descriptor/raw key/payload and temporary wire was admitted before this value-copy pass.
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = compact.inventoryServiceAt(ordinal).value
    let metadata = decodeServiceMetadata(target.lookup(chapterServiceKey(StateChapter(255),
        row.service)).value.bytes, ByteLimit(ServiceMetadataBytes))
    if metadata.error != ServiceMetadataError.None:
      return StorageContinuationResult(status: StorageContinuationError.MetadataFailure,
          metadataReason: metadata.error)
    var storage = 0
    for j in 0..<used:
      if rows[j].owner == i and rows[j].present: inc storage # Fixed scratch identities count the exact selected storage array.
    services[i] = StateService(service: row.service, metadata: metadata.value.metadata,
        storage: newSeq[StateStorageItem](storage), preimages: newSeq[StatePreimageItem](
            row.preimages),
        requests: newSeq[StateRequestItem](row.requests))
    var next = 0
    for j in 0..<used:
      if rows[j].owner == i and rows[j].present:
        services[i].storage[next] = StateStorageItem(key: rows[j].raw, value: target.lookup(rows[
            j].key).value.bytes)
        inc next # Local scratch owns these keys; only complete qualification exposes independently retained raw backing.
    for j in 0..<row.preimages:
      let fact = compact.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value
      services[i].preimages[j] = StatePreimageItem(hash: fact.hash, value: target.lookup(
          fact.key).value.bytes)
    for j in 0..<row.requests:
      var fact = compact.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
      let wire = target.lookup(requestKeys[requestCount]).value.bytes
      inc requestCount
      let decoded = decodeRequestHistory(wire, RequestHistoryConfig(items: ElementLimit(3),
          maxBytes: ByteLimit(13)))
      if decoded.error != RequestError.None:
        return StorageContinuationResult(status: StorageContinuationError.RequestFailure,
            requestReason: decoded.error)
      if decoded.value.consumed != wire.len: fail(StorageContinuationError.UnsupportedChange)
      fact.history = decoded.value.history
      services[i].requests[j] = fact
  let profile = captureCurrentProfile(update, limits.profile)
  if profile.error != CurrentProfileError.None:
    return StorageContinuationResult(status: StorageContinuationError.ProfileFailure,
        profileReason: profile)
  let globals = qualifyCurrentGlobals(profile.value, limits.globals)
  if globals.error != CurrentGlobalsError.None:
    return StorageContinuationResult(status: StorageContinuationError.GlobalsFailure,
        globalsReason: globals)
  let state = qualifyCurrentState(globals.value, services, limits.logical.inventory)
  if state.error != CurrentStateError.None:
    return StorageContinuationResult(status: StorageContinuationError.StateFailure,
        stateReason: state)
  let logical = captureCurrentLogicalState(state.value, services, limits.logical)
  if logical.error != CurrentLogicalError.None:
    return StorageContinuationResult(status: StorageContinuationError.LogicalFailure,
        logicalReason: logical)
  StorageContinuationResult(status: StorageContinuationError.None, completed: logical.value)
proc continueCurrentStorage*(parent: SelectedLogicalParent, update: PreparedCurrentChainUpdate,
    limits: StorageContinuationLimits): StorageContinuationResult =
  ## Seed only the exact original configured logical parent; caller-supplied successor declarations are unnecessary.
  let original = parent.logicalParentInventory
  if original.error != ParentLogicalError.None:
    return StorageContinuationResult(status: StorageContinuationError.InvalidParent)
  continueStorage(original.value, preserveCurrentIdentities(parent, update, limits.identity),
      update, limits)
proc continueCurrentStorage*(prior: CurrentLogicalState, update: PreparedCurrentChainUpdate,
    limits: StorageContinuationLimits): StorageContinuationResult =
  ## Continue from the genuine prior completed logical owner with full original view/Parameters checks before supported identity reconciliation.
  let original = prior.currentLogicalInventory
  if original.error != CurrentLogicalError.None:
    return StorageContinuationResult(status: StorageContinuationError.InvalidParent)
  continueStorage(original.value, preserveCurrentIdentities(prior, update, limits.identity), update, limits)
