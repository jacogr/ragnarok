# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute frozen admitted service reconstruction using actual successor payloads/metadata/histories and original namespace identities.
## Output is detached mutable declarations only; complete current logical qualification and authority remain separate.
import std/assertions
import ./refresh/plan as current_refresh_plan
import ./[request_keys as current_request_keys, identities as current_identities]
import ../supplied/logical_inventory as supplied_logical_inventory
import ../[inventory, store]
import ../accumulation/current/update as accumulation_current_update
import ../../codec/bounded
import ../../codec/state/[layout as state_layout, accounts as state_accounts,
    composition as state_composition, requests as state_requests]
type
  CurrentRefreshError* {.pure.} = enum ## Invalid plans, missing actual data, exact codec reasons and unconsumed histories remain distinct.
    Uninitialized, None, InvalidPlan, MissingValue, MetadataFailure, RequestFailure, TrailingRequest
  CurrentRefreshResult* = object ## Private selected alternatives expose only whole detached declarations or their actual typed refusal.
    case status: CurrentRefreshError
    of None:
      completed: seq[StateService]
    of MetadataFailure:
      metadataReason: ServiceMetadataError
    of RequestFailure:
      requestReason: RequestError
    else:
      discard # No partially refreshed service array escapes any refused stage.
func error*(outcome: CurrentRefreshResult): CurrentRefreshError =
  ## Observe immutable selected stage without retagging mutable output as successful.
  outcome.status
func value*(outcome: CurrentRefreshResult): seq[StateService] {.inline, requires: outcome.status ==
    CurrentRefreshError.None.} =
  ## Complete detached output remains ordinary supplied data, never a root or producer certificate.
  outcome.completed
func metadataError*(outcome: CurrentRefreshResult): ServiceMetadataError {.inline,
    requires: outcome.status == CurrentRefreshError.MetadataFailure.} =
  ## Preserve only the actual failed exact metadata decoder's reason.
  outcome.metadataReason
func requestError*(outcome: CurrentRefreshResult): RequestError {.inline,
    requires: outcome.status == CurrentRefreshError.RequestFailure.} =
  ## Preserve only the actual failed tagged history decoder's reason.
  outcome.requestReason
proc executeCurrentRefresh*(plan: CurrentRefreshPlan): CurrentRefreshResult =
  ## Accept only frozen original/target/policies; whole plan admission already bounds every output descriptor, raw key, payload and temporary wire.
  template fail(reason: CurrentRefreshError) =
    return CurrentRefreshResult(status: reason)
  let admitted = plan.refreshPlanSource
  if admitted.error != CurrentRefreshPlanError.None: fail(CurrentRefreshError.InvalidPlan)
  let source = admitted.value
  let binding = source.requestKeysSource.value
  let original = binding.identityLogical.value
  let inventory = original.suppliedInventory.value
  let target = binding.identityUpdate.value.currentUpdateState
  let limits = plan.refreshPlanLimits.value
  let count = plan.refreshPlanInfo.value.services
  var output = newSeq[StateService](count)
  # Reconstruct each original service only from the frozen actual successor.
  for i in 0..<count:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = inventory.inventoryServiceAt(ordinal).value
    let metadata = target.lookup(chapterServiceKey(StateChapter(255), row.service))
    if metadata.error != StateStoreError.None: fail(CurrentRefreshError.MissingValue)
    let raw = metadata.value.bytes
    let decoded = decodeServiceMetadata(raw, ByteLimit(ServiceMetadataBytes))
    if decoded.error != ServiceMetadataError.None:
      return CurrentRefreshResult(status: CurrentRefreshError.MetadataFailure,
          metadataReason: decoded.error)
    assert decoded.value.consumed == raw.len # Canonical version zero consumes the exact105-byte wire already admitted by the plan.
    output[i] = StateService(service: row.service, metadata: decoded.value.metadata,
      storage: newSeq[StateStorageItem](row.storage), preimages: newSeq[StatePreimageItem](
          row.preimages), requests: newSeq[StateRequestItem](row.requests))
    # Preserve original raw storage identities while refreshing admitted actual values.
    for j in 0..<row.storage:
      let index = InventoryStorageIndex(uint64(j))
      let fact = inventory.inventoryStorageAt(ordinal, index).value
      let value = target.lookup(fact.key)
      if value.error != StateStoreError.None: fail(CurrentRefreshError.MissingValue)
      output[i].storage[j] = StateStorageItem(key: original.copySuppliedStorageKey(ordinal, index,
          limits.projection.perValue).value, value: value.value.bytes)
    # Original preimage hashes select actual immutable successor payloads, including present-empty values.
    for j in 0..<row.preimages:
      let fact = inventory.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value
      let value = target.lookup(fact.key)
      if value.error != StateStoreError.None: fail(CurrentRefreshError.MissingValue)
      output[i].preimages[j] = StatePreimageItem(hash: fact.hash, value: value.value.bytes)
    # Cached physical keys select exact actual histories without deriving or substituting logical identities.
    for j in 0..<row.requests:
      let index = InventoryRequestIndex(uint64(j))
      var request = inventory.inventoryRequestAt(ordinal, index).value
      let value = target.lookup(source.currentRequestKeyAt(ordinal, index).value)
      if value.error != StateStoreError.None: fail(CurrentRefreshError.MissingValue)
      let wire = value.value.bytes
      let decoded = decodeRequestHistory(wire, RequestHistoryConfig(items: ElementLimit(3),
          maxBytes: ByteLimit(13)))
      if decoded.error != RequestError.None:
        return CurrentRefreshResult(status: CurrentRefreshError.RequestFailure,
            requestReason: decoded.error)
      if decoded.value.consumed != wire.len: fail(CurrentRefreshError.TrailingRequest)
      request.history = decoded.value.history
      output[i].requests[j] = request # Original hash/length identities stay fixed; history refreshes only from the actual successor.
  CurrentRefreshResult(status: CurrentRefreshError.None, completed: output)
