# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check the content-hash half of GP accounts eq:preimageconstraints on an exact complete inventory.
## This independent certificate does not imply request linkage, root trust or application validity.
import ../../codec/bounded
import ../../codec/state/[accounts as state_accounts, service_values as state_service_values]
import ../../crypto/primitives
import ../[inventory, manifest, store]

type
  PreimageContentLimits* = object ## Bound rows, hashes, detached individual values and aggregate input bytes before hashing.
    services*, preimages*: ElementLimit
    perValue*, totalBytes*: ByteLimit
  PreimageContentInfo* = object ## Completed hash work observations exclude metadata and request values.
    preimages*, bytes*: uint64
  CheckedPreimageContent* = object ## Only successful whole-inventory validation retains the original immutable input.
    source: StateInventory
    info: PreimageContentInfo
  PreimageContentError* {.pure.} = enum ## Resource refusal, malformed content and backend refusal remain distinct.
    Uninitialized, None, InvalidSource, LimitExceeded, BackendFailure, HashMismatch
  PreimageContentResult*[T] = object ## Failed results never expose a partial content certificate.
    case status: PreimageContentError
    of None:
      completed: T
    of BackendFailure, HashMismatch:
      service: ServiceIndex
      ordinal: InventoryPreimageIndex
    else:
      discard
func error*[T](outcome: PreimageContentResult[T]): PreimageContentError =
  ## Read the reason without allowing callers to retag a failure.
  outcome.status
func value*[T](outcome: PreimageContentResult[T]): T {.inline,
    requires: outcome.status == PreimageContentError.None.} =
  ## Only complete successful validation exposes source-bearing authority.
  outcome.completed
func failedService*[T](outcome: PreimageContentResult[T]): ServiceIndex {.inline,
    requires: outcome.status in {PreimageContentError.BackendFailure,
        PreimageContentError.HashMismatch}.} =
  ## A real hash attempt identifies its original service, unlike a preflight refusal.
  outcome.service
func failedPreimage*[T](outcome: PreimageContentResult[T]): InventoryPreimageIndex {.inline,
    requires: outcome.status in {PreimageContentError.BackendFailure,
        PreimageContentError.HashMismatch}.} =
  ## The preimage ordinal is local to the failed service in the original inventory.
  outcome.ordinal
proc auditPreimageContent*(source: StateInventory,
    limits: PreimageContentLimits): PreimageContentResult[CheckedPreimageContent] =
  ## Preflight every captured extent before copying a value or requesting a content hash.
  template fail(reason: PreimageContentError) =
    return PreimageContentResult[CheckedPreimageContent](status: reason)
  let info = source.inventoryInfo
  if info.error != StateInventoryError.None:
    fail(PreimageContentError.InvalidSource) # Defaults cannot prove complete preimage enumeration.
  if uint64(info.value.services) > uint64(limits.services):
    fail(PreimageContentError.LimitExceeded) # Bound the row inspection itself.
  var remaining = uint64(limits.preimages)
  var bytes = uint64(limits.totalBytes)
  for i in 0..<info.value.services:
    let index = InventoryServiceIndex(uint64(i))
    let row = source.inventoryServiceAt(index).value
    if uint64(row.preimages) > remaining:
      fail(PreimageContentError.LimitExceeded) # Count zero-length values as hash work too.
    remaining -= uint64(row.preimages)
    for j in 0..<row.preimages:
      let fact = source.inventoryPreimageAt(index, InventoryPreimageIndex(uint64(j))).value
      if fact.bytes > uint64(limits.perValue) or fact.bytes > bytes:
        fail(PreimageContentError.LimitExceeded) # Native extents were already validated by exact capture.
      bytes -= fact.bytes # No aggregate byte addition can overflow.
  let snapshot = source.inventorySource.value.manifestSource.value
  for i in 0..<info.value.services:
    let index = InventoryServiceIndex(uint64(i))
    let row = source.inventoryServiceAt(index).value
    for j in 0..<row.preimages:
      let ordinal = InventoryPreimageIndex(uint64(j))
      let fact = source.inventoryPreimageAt(index, ordinal).value
      let found = snapshot.lookup(fact.key)
      if found.error != StateStoreError.None:
        fail(PreimageContentError.InvalidSource) # Captured physical identity must still belong to its retained source.
      if uint64(found.value.byteLength) != fact.bytes:
        fail(PreimageContentError.InvalidSource) # A different extent can never replace the preflighted payload.
      let digest = blake2b256(found.value.bytes)
      if digest.error != CryptoError.None:
        return PreimageContentResult[CheckedPreimageContent](
          status: PreimageContentError.BackendFailure,
          service: row.service, ordinal: ordinal) # Preserve backend refusal without publishing earlier successful hashes.
      if array[32, byte](digest.value) != array[32, byte](fact.hash):
        return PreimageContentResult[CheckedPreimageContent](
          status: PreimageContentError.HashMismatch,
          service: row.service, ordinal: ordinal) # Raw value bytes alone determine the declared Blake2b-256 hash.
  PreimageContentResult[CheckedPreimageContent](status: PreimageContentError.None,
    completed: CheckedPreimageContent(source: source,
      info: PreimageContentInfo(preimages: uint64(limits.preimages)-remaining, bytes: uint64(
          limits.totalBytes)-bytes)))
proc contentInfo*(checked: CheckedPreimageContent): PreimageContentResult[PreimageContentInfo] =
  ## Copy only completed bounded hashing observations.
  if checked.source.inventoryInfo.error != StateInventoryError.None:
    return PreimageContentResult[PreimageContentInfo](
        status: PreimageContentError.Uninitialized) # Default certificate.
  PreimageContentResult[PreimageContentInfo](status: PreimageContentError.None,
      completed: checked.info)
proc contentInventory*(checked: CheckedPreimageContent): PreimageContentResult[StateInventory] =
  ## Retain the original exact owner without constructing a new equal source.
  if checked.source.inventoryInfo.error != StateInventoryError.None:
    return PreimageContentResult[StateInventory](status: PreimageContentError.Uninitialized) # Default certificate.
  PreimageContentResult[StateInventory](status: PreimageContentError.None,
      completed: checked.source)
