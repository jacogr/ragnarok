# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reconstruct complete current logical state across producer-proven storage/request identity changes while preserving exact original parent, selected rollback and genuine successor provenance.
import ./[parent_logical, current_logical, current_identities, accumulation_current_update,
    accumulation_storage_history, accumulation_effects, supplied_logical_inventory,
    supplied_services, inventory, store, current_profile, current_globals, current_state,
    global_snapshot, request_identity_history]
import ../codec/[bounded, state_layout, state_composition, state_accounts, state_requests]
type
  LogicalContinuationLimits* = object ## Original binding, admitted identity scratch, bounded planning and whole output/current qualification retain independent policies.
    identity*: CurrentIdentityLimits
    checks*: ElementLimit
    scratchBytes*: ByteLimit
    projection*: SuppliedServicesLimits
    profile*: CurrentProfileLimits
    globals*: GlobalStateLimits
    logical*: SuppliedLogicalLimits
  LogicalContinuationError* {.pure.} = enum ## Unsupported namespaces, missing producer capture, exact source and genuine typed qualification refusal expose no prefix.
    Uninitialized, None, InvalidParent, IdentityFailure, MissingStorageEvidence, LimitExceeded,
    UnsupportedChange, MetadataFailure, RequestFailure, ProfileFailure, GlobalsFailure,
    StateFailure, LogicalFailure, MissingRequestEvidence
  LogicalContinuationResult* = object ## Only complete original-current and raw-key requalification exposes a logical successor.
    case status: LogicalContinuationError
    of None: completed: CurrentLogicalState
    of IdentityFailure: identityReason: CurrentIdentityResult[PreservedCurrentIdentities]
    of MetadataFailure: metadataReason: ServiceMetadataError
    of RequestFailure: requestReason: RequestError
    of ProfileFailure: profileReason: CurrentProfileResult[DerivedCurrentProfile]
    of GlobalsFailure: globalsReason: CurrentGlobalsResult[CurrentGlobalSerialization]
    of StateFailure: stateReason: CurrentStateResult[CurrentStateSerialization]
    of LogicalFailure: logicalReason: CurrentLogicalResult[CurrentLogicalState]
    else: discard # No candidate service declarations or successful earlier certificate escapes.
  StorageContinuationLimits* = LogicalContinuationLimits ## Compatibility alias preserves existing storage-only policies and representation.
  StorageContinuationError* = LogicalContinuationError ## Existing error members/ordinals remain stable; request evidence refusal is appended.
  StorageContinuationResult* = LogicalContinuationResult ## Compatibility alias retains the same private guarded payload contract.
  ContinuationKind {.pure.} = enum ## Closed implementation variants share original source validation and complete qualification.
    StorageOnly, StorageAndRequests
  RequestIdentityRow = object ## Admitted private request planning retains exact logical identity and final presence for this actual target.
    owner: int
    key: StateKey
    item: StateRequestItem
    present, original, produced: bool
  StorageIdentityRow = object ## Admitted private scratch owns raw identities; presence and evidence remain bound to this exact target.
    owner: int
    key: StateKey
    raw: seq[byte]
    present, original, produced: bool
func error*(outcome: LogicalContinuationResult): LogicalContinuationError =
  ## Observe the immutable selected continuation stage.
  outcome.status
func value*(outcome: LogicalContinuationResult): CurrentLogicalState {.inline,
    requires: outcome.status == LogicalContinuationError.None.} =
  ## Complete original current qualification alone grants a retained logical successor.
  outcome.completed
func identityFailure*(outcome: LogicalContinuationResult): CurrentIdentityResult[
    PreservedCurrentIdentities] {.inline, requires: outcome.status ==
    LogicalContinuationError.IdentityFailure.} =
  ## Preserve actual original state/view/Parameters/resource refusal; accepted identity changes never appear as a failed source prefix.
  outcome.identityReason
func metadataError*(outcome: LogicalContinuationResult): ServiceMetadataError {.inline,
    requires: outcome.status == LogicalContinuationError.MetadataFailure.} =
  ## Preserve exact current metadata decoding refusal.
  outcome.metadataReason
func requestError*(outcome: LogicalContinuationResult): RequestError {.inline,
    requires: outcome.status == LogicalContinuationError.RequestFailure.} =
  ## Preserve actual request key or history decoding refusal.
  outcome.requestReason
func profileFailure*(outcome: LogicalContinuationResult): CurrentProfileResult[
    DerivedCurrentProfile] {.inline, requires: outcome.status ==
    LogicalContinuationError.ProfileFailure.} =
  ## Preserve independently bounded original-current profile qualification refusal.
  outcome.profileReason
func globalsFailure*(outcome: LogicalContinuationResult): CurrentGlobalsResult[
    CurrentGlobalSerialization] {.inline, requires: outcome.status ==
    LogicalContinuationError.GlobalsFailure.} =
  ## Preserve exact all-global decoding refusal on the original successor.
  outcome.globalsReason
func stateFailure*(outcome: LogicalContinuationResult): CurrentStateResult[
    CurrentStateSerialization] {.inline, requires: outcome.status ==
    LogicalContinuationError.StateFailure.} =
  ## Preserve complete actual-map mismatch, including unsupported added namespaces.
  outcome.stateReason
func logicalFailure*(outcome: LogicalContinuationResult): CurrentLogicalResult[
    CurrentLogicalState] {.inline, requires: outcome.status ==
    LogicalContinuationError.LogicalFailure.} =
  ## Preserve late raw-key/current-bound capture refusal without successful prefix authority.
  outcome.logicalReason
proc continueLogical[kind: static[ContinuationKind]](original: SuppliedLogicalInventory,
    binding: CurrentIdentityResult[PreservedCurrentIdentities], update: PreparedCurrentChainUpdate,
    limits: LogicalContinuationLimits): LogicalContinuationResult =
  ## Accept strict identity-set refusal only after that API has validated every original parent/view/full-Parameters boundary; reconcile storage from this update's own producer evidence.
  template fail(reason: LogicalContinuationError) =
    return LogicalContinuationResult(status: reason)
  if binding.error notin {CurrentIdentityError.None, CurrentIdentityError.NewIdentity,
      CurrentIdentityError.MissingIdentity}:
    return LogicalContinuationResult(status: LogicalContinuationError.IdentityFailure,
        identityReason: binding)
  if not update.hasStorageHistory: fail(LogicalContinuationError.MissingStorageEvidence)
  let history = update.currentUpdateStorageHistory
  let produced = history.storageHistoryInfo.value
  var requests = default(RequestIdentityHistory)
  var requestInfo = default(RequestIdentityHistoryInfo)
  when kind == ContinuationKind.StorageAndRequests:
    if not update.hasRequestHistory: fail(LogicalContinuationError.MissingRequestEvidence)
    requests = update.currentUpdateRequestHistory
    requestInfo = requests.requestIdentityHistoryInfo.value
  let compact = original.suppliedInventory.value
  let info = compact.inventoryInfo.value
  let raw = original.suppliedLogicalInfo.value
  let target = update.currentUpdateState
  if uint64(info.services) > uint64(limits.projection.services): fail(
      LogicalContinuationError.LimitExceeded)
  if info.services > 0:
    let minimum = uint64(sizeof(StateService)+ServiceMetadataBytes)
    if uint64(limits.projection.perValue) < uint64(ServiceMetadataBytes) or
        uint64(info.services) > min(uint64(limits.projection.bytes), uint64(high(int))) div minimum:
      fail(LogicalContinuationError.LimitExceeded) # Admit the fixed minimum descriptors and metadata wires before request namespace hashing.
  var scratch = min(uint64(limits.scratchBytes), uint64(high(int)))
  let slots = scratch div uint64(sizeof(StorageIdentityRow))
  if raw.keys > slots or uint64(produced.facts) > slots-raw.keys: fail(
      LogicalContinuationError.LimitExceeded)
  let capacity = raw.keys+uint64(produced.facts)
  scratch -= capacity*uint64(sizeof(StorageIdentityRow))
  var requestCapacity = 0'u64
  when kind == ContinuationKind.StorageOnly:
    if info.facts > scratch div uint64(sizeof(StateKey)): fail(
        LogicalContinuationError.LimitExceeded)
    scratch -= info.facts*uint64(sizeof(StateKey))
  else:
    let requestSlots = scratch div uint64(sizeof(RequestIdentityRow))
    if info.facts > requestSlots or uint64(requestInfo.facts) > requestSlots-info.facts:
      fail(LogicalContinuationError.LimitExceeded)
    requestCapacity = info.facts+uint64(requestInfo.facts)
    scratch -= requestCapacity*uint64(sizeof(RequestIdentityRow)) # Complete worst-case request planning storage is admitted before allocation.
  if raw.rawKeyBytes > scratch: fail(LogicalContinuationError.LimitExceeded)
  scratch -= raw.rawKeyBytes
  if uint64(produced.facts) > produced.bytes div uint64(sizeof(StorageHistoryRow)):
    fail(LogicalContinuationError.LimitExceeded) # Prove descriptor multiplication against the immutable captured byte ledger.
  let descriptors = uint64(produced.facts)*uint64(sizeof(StorageHistoryRow))
  if descriptors > produced.bytes or produced.bytes-descriptors > scratch:
    fail(LogicalContinuationError.LimitExceeded) # All possible raw copies, identity rows and request-key scratch fit before allocation.
  var rows = newSeq[StorageIdentityRow](int(capacity))
  var requestKeys: seq[StateKey] = @[]
  var requestRows: seq[RequestIdentityRow] = @[]
  var requestUsed = 0
  when kind == ContinuationKind.StorageOnly:
    requestKeys = newSeq[StateKey](int(info.facts))
  else:
    requestRows = newSeq[RequestIdentityRow](int(requestCapacity))
  var used = 0
  var work = uint64(limits.checks)
  template spend() =
    if work == 0: fail(LogicalContinuationError.LimitExceeded)
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
          LogicalContinuationError.LimitExceeded)
      let found = target.lookup(fact.key)
      if found.error notin {StateStoreError.None, StateStoreError.MissingKey}: fail(
          LogicalContinuationError.UnsupportedChange)
      rows[used] = StorageIdentityRow(owner: i, key: fact.key,
          raw: original.copySuppliedStorageKey(service, index, limits.projection.perValue).value,
          present: found.error == StateStoreError.None, original: true, produced: false)
      inc used # Original qualified counts fit the admitted fixed identity scratch.
    when kind == ContinuationKind.StorageAndRequests:
      for j in 0..<row.requests:
        spend()
        let item = compact.inventoryRequestAt(service, InventoryRequestIndex(uint64(j))).value
        let key = serviceRequestKey(row.service, item.hash, item.length, ByteLimit(32))
        if key.error != RequestError.None:
          return LogicalContinuationResult(status: LogicalContinuationError.RequestFailure,
              requestReason: key.error)
        let found = target.lookup(key.value)
        if found.error notin {StateStoreError.None, StateStoreError.MissingKey}: fail(
            LogicalContinuationError.UnsupportedChange)
        requestRows[requestUsed] = RequestIdentityRow(owner: i, key: key.value, item: item,
            present: found.error == StateStoreError.None, original: true, produced: false)
        inc requestUsed # Original compact fact count bounds the admitted request planning prefix.
  for i in 0..<produced.facts:
    spend()
    let fact = history.storageHistoryAt(StorageHistoryIndex(uint64(i))).value.fact
    let details = fact.storageFactInfo.value
    if uint64(details.rawBytes) > uint64(limits.projection.perValue): fail(
        LogicalContinuationError.LimitExceeded)
    var owner = -1
    for j in 0..<info.services:
      spend()
      if uint32(compact.inventoryServiceAt(InventoryServiceIndex(uint64(j))).value.service) ==
          uint32(details.service): owner = j
    if owner < 0: fail(LogicalContinuationError.UnsupportedChange) # Service creation/deletion needs its own producer contract.
    let key = fact.copyStorageFactKey(limits.projection.perValue).value
    var selected = -1
    for j in 0..<used:
      spend()
      if rows[j].owner == owner and array[31, byte](rows[j].key) == array[31, byte](
          details.key): selected = j
    if selected >= 0:
      if rows[selected].raw != key: fail(LogicalContinuationError.UnsupportedChange) # Physical equality cannot replace exact original raw identity.
      rows[selected].produced = true
    else:
      let found = target.lookup(details.key)
      if found.error notin {StateStoreError.None, StateStoreError.MissingKey}: fail(
          LogicalContinuationError.UnsupportedChange)
      rows[used] = StorageIdentityRow(owner: owner, key: details.key, raw: key,
          present: found.error == StateStoreError.None, original: false, produced: true)
      inc used # Multiple selected invocations coalesce only identical raw storage identities.
  when kind == ContinuationKind.StorageAndRequests:
    for i in 0..<requestInfo.facts:
      spend()
      let fact = requests.requestIdentityHistoryAt(RequestIdentityHistoryIndex(uint64(i))).value.fact
      var owner = -1
      for j in 0..<info.services:
        spend()
        if uint32(compact.inventoryServiceAt(InventoryServiceIndex(uint64(j))).value.service) ==
            uint32(fact.service): owner = j
      if owner < 0: fail(LogicalContinuationError.UnsupportedChange) # A new account still needs its own selected creation contract.
      var selected = -1
      for j in 0..<requestUsed:
        spend()
        if requestRows[j].owner == owner and array[31, byte](requestRows[j].key) == array[31, byte](
            fact.key): selected = j
      if selected >= 0:
        let originalRequest = requestRows[selected].item
        if array[32, byte](originalRequest.hash) != array[32, byte](fact.hash) or uint32(
            originalRequest.length) != uint32(fact.length):
          fail(LogicalContinuationError.UnsupportedChange) # Do not replace logical identity on a physical collision.
        requestRows[selected].produced = true
      else:
        let found = target.lookup(fact.key)
        if found.error notin {StateStoreError.None, StateStoreError.MissingKey}: fail(
            LogicalContinuationError.UnsupportedChange)
        requestRows[requestUsed] = RequestIdentityRow(owner: owner, key: fact.key,
            item: StateRequestItem(hash: fact.hash, length: fact.length, history: requestedHistory(
          )),
            present: found.error == StateStoreError.None, original: false, produced: true)
        inc requestUsed # Selected request identities coalesce only exact original service/hash/length bindings.
  var bytes = min(uint64(limits.projection.bytes), uint64(high(int)))
  var facts = uint64(limits.projection.facts)
  template charge(count: int, kind: untyped) =
    block:
      let extent = uint64(count)
      if extent > facts or extent > bytes div uint64(sizeof(kind)): fail(
          LogicalContinuationError.LimitExceeded)
      facts -= extent
      bytes -= extent*uint64(sizeof(kind))
  template payload(size: uint64) =
    block:
      let extent = size
      if extent > uint64(limits.projection.perValue) or extent > bytes: fail(
          LogicalContinuationError.LimitExceeded)
      bytes -= extent
  charge(info.services, StateService)
  var requestCount = 0
  for i in 0..<info.services:
    spend()
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = compact.inventoryServiceAt(ordinal).value
    let metadata = target.lookup(chapterServiceKey(StateChapter(255), row.service))
    if metadata.error != StateStoreError.None: fail(LogicalContinuationError.UnsupportedChange)
    if metadata.value.byteLength != ServiceMetadataBytes: fail(
        LogicalContinuationError.UnsupportedChange)
    payload(uint64(ServiceMetadataBytes)) # Actual codec wires have explicit temporary copy admission too.
    var storage = 0
    for j in 0..<used:
      spend()
      if rows[j].owner == i:
        if rows[j].original and not rows[j].present and not rows[j].produced:
          fail(LogicalContinuationError.UnsupportedChange) # No deletion is inferred from an unexplained map difference.
        if rows[j].present:
          inc storage
          payload(uint64(rows[j].raw.len))
          payload(uint64(target.lookup(rows[j].key).value.byteLength))
    charge(storage, StateStorageItem)
    charge(row.preimages, StatePreimageItem)
    when kind == ContinuationKind.StorageOnly:
      charge(row.requests, StateRequestItem)
    else:
      var selectedRequests = 0
      for j in 0..<requestUsed:
        spend()
        if requestRows[j].owner == i:
          if requestRows[j].original and not requestRows[j].present and not requestRows[j].produced:
            fail(LogicalContinuationError.UnsupportedChange) # No unexplained original request removal is inferred absent.
          if requestRows[j].present:
            inc selectedRequests
            let value = target.lookup(requestRows[j].key).value
            if value.byteLength > 13: fail(LogicalContinuationError.UnsupportedChange)
            payload(uint64(value.byteLength))
      charge(selectedRequests, StateRequestItem)
    for j in 0..<row.preimages:
      spend()
      let fact = compact.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value
      let value = target.lookup(fact.key)
      if value.error != StateStoreError.None: fail(LogicalContinuationError.UnsupportedChange)
      payload(uint64(value.value.byteLength))
    when kind == ContinuationKind.StorageOnly:
      for j in 0..<row.requests:
        spend()
        let fact = compact.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
        let key = serviceRequestKey(row.service, fact.hash, fact.length, ByteLimit(32))
        if key.error != RequestError.None:
          return LogicalContinuationResult(status: LogicalContinuationError.RequestFailure,
              requestReason: key.error)
        requestKeys[requestCount] = key.value
        inc requestCount # Original compact fact count bounds this admitted request-key array.
        let value = target.lookup(key.value)
        if value.error != StateStoreError.None: fail(LogicalContinuationError.UnsupportedChange)
        if value.value.byteLength > 13: fail(LogicalContinuationError.UnsupportedChange)
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
      return LogicalContinuationResult(status: LogicalContinuationError.MetadataFailure,
          metadataReason: metadata.error)
    var storage = 0
    for j in 0..<used:
      if rows[j].owner == i and rows[j].present: inc storage # Fixed scratch identities count the exact selected storage array.
    var requestCountForService = row.requests
    when kind == ContinuationKind.StorageAndRequests:
      requestCountForService = 0
      for j in 0..<requestUsed:
        if requestRows[j].owner == i and requestRows[j].present: inc requestCountForService
    services[i] = StateService(service: row.service, metadata: metadata.value.metadata,
        storage: newSeq[StateStorageItem](storage), preimages: newSeq[StatePreimageItem](
            row.preimages),
        requests: newSeq[StateRequestItem](requestCountForService))
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
    when kind == ContinuationKind.StorageOnly:
      for j in 0..<row.requests:
        var fact = compact.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
        let wire = target.lookup(requestKeys[requestCount]).value.bytes
        inc requestCount
        let decoded = decodeRequestHistory(wire, RequestHistoryConfig(items: ElementLimit(3),
            maxBytes: ByteLimit(13)))
        if decoded.error != RequestError.None:
          return LogicalContinuationResult(status: LogicalContinuationError.RequestFailure,
              requestReason: decoded.error)
        if decoded.value.consumed != wire.len: fail(LogicalContinuationError.UnsupportedChange)
        fact.history = decoded.value.history
        services[i].requests[j] = fact
    else:
      var copied = 0
      for j in 0..<requestUsed:
        if requestRows[j].owner == i and requestRows[j].present:
          var item = requestRows[j].item
          let wire = target.lookup(requestRows[j].key).value.bytes
          let decoded = decodeRequestHistory(wire, RequestHistoryConfig(items: ElementLimit(3),
              maxBytes: ByteLimit(13)))
          if decoded.error != RequestError.None:
            return LogicalContinuationResult(status: LogicalContinuationError.RequestFailure,
                requestReason: decoded.error)
          if decoded.value.consumed != wire.len: fail(LogicalContinuationError.UnsupportedChange)
          item.history = decoded.value.history
          services[i].requests[copied] = item
          inc copied # Complete selected request output was counted and wire-admitted before all value copying.
  let profile = captureCurrentProfile(update, limits.profile)
  if profile.error != CurrentProfileError.None:
    return LogicalContinuationResult(status: LogicalContinuationError.ProfileFailure,
        profileReason: profile)
  let globals = qualifyCurrentGlobals(profile.value, limits.globals)
  if globals.error != CurrentGlobalsError.None:
    return LogicalContinuationResult(status: LogicalContinuationError.GlobalsFailure,
        globalsReason: globals)
  let state = qualifyCurrentState(globals.value, services, limits.logical.inventory)
  if state.error != CurrentStateError.None:
    return LogicalContinuationResult(status: LogicalContinuationError.StateFailure,
        stateReason: state)
  let logical = captureCurrentLogicalState(state.value, services, limits.logical)
  if logical.error != CurrentLogicalError.None:
    return LogicalContinuationResult(status: LogicalContinuationError.LogicalFailure,
        logicalReason: logical)
  LogicalContinuationResult(status: LogicalContinuationError.None, completed: logical.value)
proc continueCurrentStorage*(parent: SelectedLogicalParent, update: PreparedCurrentChainUpdate,
    limits: LogicalContinuationLimits): LogicalContinuationResult =
  ## Seed only the exact original configured logical parent; caller-supplied successor declarations are unnecessary.
  let original = parent.logicalParentInventory
  if original.error != ParentLogicalError.None:
    return LogicalContinuationResult(status: LogicalContinuationError.InvalidParent)
  continueLogical[ContinuationKind.StorageOnly](original.value, preserveCurrentIdentities(parent,
      update, limits.identity), update, limits)
proc continueCurrentStorage*(prior: CurrentLogicalState, update: PreparedCurrentChainUpdate,
    limits: LogicalContinuationLimits): LogicalContinuationResult =
  ## Continue from the genuine prior completed logical owner with full original view/Parameters checks before supported identity reconciliation.
  let original = prior.currentLogicalInventory
  if original.error != CurrentLogicalError.None:
    return LogicalContinuationResult(status: LogicalContinuationError.InvalidParent)
  continueLogical[ContinuationKind.StorageOnly](original.value, preserveCurrentIdentities(prior,
      update, limits.identity), update, limits)

proc continueCurrentNamespaces*(parent: SelectedLogicalParent, update: PreparedCurrentChainUpdate,
    limits: LogicalContinuationLimits): LogicalContinuationResult =
  ## Continue storage and request identities using only this update's own selected evidence and the exact original configured logical parent.
  let original = parent.logicalParentInventory
  if original.error != ParentLogicalError.None:
    return LogicalContinuationResult(status: LogicalContinuationError.InvalidParent)
  continueLogical[ContinuationKind.StorageAndRequests](original.value, preserveCurrentIdentities(
      parent, update, limits.identity), update, limits)
proc continueCurrentNamespaces*(prior: CurrentLogicalState, update: PreparedCurrentChainUpdate,
    limits: LogicalContinuationLimits): LogicalContinuationResult =
  ## Repeated actual successors retain original completed logical provenance; no replacement producer history or supplied successor array is accepted.
  let original = prior.currentLogicalInventory
  if original.error != CurrentLogicalError.None:
    return LogicalContinuationResult(status: LogicalContinuationError.InvalidParent)
  continueLogical[ContinuationKind.StorageAndRequests](original.value, preserveCurrentIdentities(
      prior, update, limits.identity), update, limits)
