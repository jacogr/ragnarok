# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded physical request-key companion for exact original-to-genuine-current identity preservation.
## Compact inventories retain logical request identity/history; this separate owner admits and caches key derivation once.
import ./current_identities as state_current_identities
import ./supplied_logical_inventory as state_supplied_logical_inventory
import ./inventory as state_inventory
import ../codec/bounded as codec_bounded
import ../codec/state_layout as codec_state_layout
import ../codec/state_requests as codec_state_requests
type
  CurrentRequestKeyLimits* = object ## Whole native row/key arrays and primitive call count are admitted before allocation or hashing.
    services*, requests*: ElementLimit
    bytes*: ByteLimit
  CurrentRequestKeyInfo* = object ## Copied fixed accounting describes request derivation work, not payload validity or producer events.
    services*: int
    requests*, bytes*: uint64
  RequestKeyRow = object # Private arrays are fixed to original complete logical service/request ordinals.
    keys: seq[StateKey]
  RequestKeyData = ref object # One immutable acyclic source/array owner makes retained handles allocation-free.
    source: PreservedCurrentIdentities
    rows: seq[RequestKeyRow]
    info: CurrentRequestKeyInfo
  CurrentRequestKeys* = object ## Only bounded complete successful derivation constructs original-source physical request identities.
    data: nil RequestKeyData
  CurrentRequestKeyError* {.pure.} = enum ## Invalid original source, resource refusal, actual codec/backend reason and bad nominal ordinals stay distinct.
    Uninitialized, None, InvalidSource, LimitExceeded, RequestFailure, InvalidIndex
  CurrentRequestKeyResult*[T] = object ## Private failed/default alternatives expose no successful prefix or partially filled key arrays.
    case status: CurrentRequestKeyError
    of None:
      completed: T
    of RequestFailure:
      requestReason: RequestError
    else:
      discard # No retained continuation source escapes a refused derivation.
func error*[T](outcome: CurrentRequestKeyResult[T]): CurrentRequestKeyError =
  ## Read selected immutable stage only.
  outcome.status
func value*[T](outcome: CurrentRequestKeyResult[T]): T {.inline, requires: outcome.status ==
    CurrentRequestKeyError.None.} =
  ## Extract only fully successful original-key companions or fixed observations.
  outcome.completed
func requestError*[T](outcome: CurrentRequestKeyResult[T]): RequestError {.inline,
    requires: outcome.status == CurrentRequestKeyError.RequestFailure.} =
  ## Preserve exact original request key codec/backend refusal without reclassifying it as absence or limits.
  outcome.requestReason
proc captureCurrentRequestKeys*(source: PreservedCurrentIdentities,
    limits: CurrentRequestKeyLimits): CurrentRequestKeyResult[CurrentRequestKeys] =
  ## Admit all descriptor arrays and finite key work before derivation; no actual successor payload is copied or decoded.
  template fail(reason: CurrentRequestKeyError) =
    return CurrentRequestKeyResult[CurrentRequestKeys](status: reason)
  let original = source.identityLogical
  if original.error != CurrentIdentityError.None: fail(CurrentRequestKeyError.InvalidSource)
  let inventory = original.value.suppliedInventory.value
  let count = inventory.inventoryInfo.value.services
  if uint64(count) > uint64(limits.services): fail(CurrentRequestKeyError.LimitExceeded)
  var available = min(uint64(limits.bytes), uint64(high(int)))
  let budget = available
  if uint64(count) > available div uint64(sizeof(RequestKeyRow)):
    fail(CurrentRequestKeyError.LimitExceeded) # Division proves native row allocation and multiplication.
  available-=uint64(count)*uint64(sizeof(RequestKeyRow))
  var requests = uint64(limits.requests)
  for i in 0..<count:
    let row = inventory.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    let amount = uint64(row.requests)
    if amount > requests or amount > available div uint64(sizeof(StateKey)):
      fail(CurrentRequestKeyError.LimitExceeded) # Whole logical request cardinality and native key arrays are admitted before any primitive.
    requests-=amount
    available-=amount*uint64(sizeof(StateKey))
  var rows = newSeq[RequestKeyRow](count)
  for i in 0..<count:
    let service = InventoryServiceIndex(uint64(i))
    let row = inventory.inventoryServiceAt(service).value
    rows[i].keys = newSeq[StateKey](row.requests)
    for j in 0..<row.requests:
      let request = inventory.inventoryRequestAt(service, InventoryRequestIndex(uint64(j))).value
      let key = serviceRequestKey(row.service, request.hash, request.length, ByteLimit(32))
      if key.error != RequestError.None:
        return CurrentRequestKeyResult[CurrentRequestKeys](
            status: CurrentRequestKeyError.RequestFailure,
            requestReason: key.error) # Drop every actual partial array; no usable owner escapes backend refusal.
      rows[i].keys[j] = key.value
  CurrentRequestKeyResult[CurrentRequestKeys](status: CurrentRequestKeyError.None,
    completed: CurrentRequestKeys(data: RequestKeyData(source: source, rows: rows,
      info: CurrentRequestKeyInfo(services: count, requests: uint64(limits.requests)-requests,
          bytes: budget-available))))
proc requestKeysSource*(source: CurrentRequestKeys): CurrentRequestKeyResult[
    PreservedCurrentIdentities] =
  ## Retain exact original-parent/genuine-update provenance, never a caller supplied target or replacement logical map.
  let data = source.data
  if data == nil: return CurrentRequestKeyResult[PreservedCurrentIdentities](
      status: CurrentRequestKeyError.Uninitialized)
  CurrentRequestKeyResult[PreservedCurrentIdentities](status: CurrentRequestKeyError.None,
      completed: data.source)
proc requestKeysInfo*(source: CurrentRequestKeys): CurrentRequestKeyResult[CurrentRequestKeyInfo] =
  ## Copy successful fixed retention/work accounting without mutable array exposure.
  let data = source.data
  if data == nil: return CurrentRequestKeyResult[CurrentRequestKeyInfo](
      status: CurrentRequestKeyError.Uninitialized)
  CurrentRequestKeyResult[CurrentRequestKeyInfo](status: CurrentRequestKeyError.None,
      completed: data.info)
proc currentRequestKeyAt*(source: CurrentRequestKeys, service: InventoryServiceIndex,
    request: InventoryRequestIndex): CurrentRequestKeyResult[StateKey] =
  ## Full-width nominal ordinals are checked before narrowing; copied fixed keys require no allocation or hash.
  let data = source.data
  if data == nil: return CurrentRequestKeyResult[StateKey](
      status: CurrentRequestKeyError.Uninitialized)
  if uint64(service) >= uint64(data.rows.len): return CurrentRequestKeyResult[StateKey](
      status: CurrentRequestKeyError.InvalidIndex)
  if uint64(request) >= uint64(data.rows[int(uint64(
      service))].keys.len): return CurrentRequestKeyResult[StateKey](
      status: CurrentRequestKeyError.InvalidIndex)
  CurrentRequestKeyResult[StateKey](status: CurrentRequestKeyError.None, completed: data.rows[int(
      uint64(service))].keys[int(uint64(request))])
