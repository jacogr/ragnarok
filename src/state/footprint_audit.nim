# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded source-bound account footprint equations certify only dependent metadata fields.
## Complete inventory provenance survives; preimage content, economics and STF validity remain separate.
import ../codec/bounded
import ../codec/state/accounts as state_accounts
import ./inventory
import ./account/footprint as account_footprint

type
  FootprintAuditLimits* = object ## Service rows and traversed storage/request facts have independent bounds.
    services*, checks*: ElementLimit
  FootprintAuditInfo* = object ## Completed work counts include each service row and each dependent fact.
    services*: int
    checks*: uint64
  CheckedAccountFootprints* = object ## A private original inventory binds all certified metadata to its exact owner.
    source: StateInventory
    info: FootprintAuditInfo
  FootprintAuditError* {.pure.} = enum ## Mismatches and arithmetic/resource refusals never expose a success prefix.
    Uninitialized, None, InvalidSource, LimitExceeded, Overflow, ItemsMismatch, BytesMismatch, InvalidIndex
  FootprintAuditResult*[T] = object ## Only actual service failures carry an offending nominal location.
    case status: FootprintAuditError
    of None:
      completed: T
    of Overflow, ItemsMismatch, BytesMismatch:
      service: ServiceIndex
      ordinal: InventoryServiceIndex
    else:
      discard

func error*[T](outcome: FootprintAuditResult[T]): FootprintAuditError =
  ## Inspect the immutable reason without access to its discriminator.
  outcome.status

func value*[T](outcome: FootprintAuditResult[T]): T {.inline,
    requires: outcome.status == FootprintAuditError.None.} =
  ## Only complete successful checks grant access to their source-bound result.
  outcome.completed

func failedService*[T](outcome: FootprintAuditResult[T]): ServiceIndex {.inline,
    requires: outcome.status in {FootprintAuditError.Overflow, FootprintAuditError.ItemsMismatch,
      FootprintAuditError.BytesMismatch}.} =
  ## Resource refusals and defaults do not invent an offending account.
  outcome.service

func failedOrdinal*[T](outcome: FootprintAuditResult[T]): InventoryServiceIndex {.inline,
    requires: outcome.status in {FootprintAuditError.Overflow, FootprintAuditError.ItemsMismatch,
      FootprintAuditError.BytesMismatch}.} =
  ## The location belongs to the caller's original immutable inventory order.
  outcome.ordinal

proc auditAccountFootprints*(source: StateInventory,
    limits: FootprintAuditLimits): FootprintAuditResult[CheckedAccountFootprints] =
  ## Preflight complete work before computing any footprint; no hashing, payload copying or output arrays.
  template fail(reason: FootprintAuditError) =
    return FootprintAuditResult[CheckedAccountFootprints](status: reason)
  let info = source.inventoryInfo
  if info.error != StateInventoryError.None:
    fail(FootprintAuditError.InvalidSource) # Default inventory supplies no complete source.
  if uint64(info.value.services) > uint64(limits.services):
    fail(FootprintAuditError.LimitExceeded) # Bound the initial row inspection loop.
  var remaining = uint64(limits.checks)
  template charge(amount: uint64) =
    if amount > remaining:
      fail(FootprintAuditError.LimitExceeded)
    remaining -= amount # Subtraction proves the entire row/fact work budget without wrapping.
  charge(uint64(info.value.services))
  for i in 0..<info.value.services:
    let row = source.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    charge(uint64(row.storage))
    charge(uint64(row.requests)) # Preimages add no separate dependent footprint term.
  for i in 0..<info.value.services:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = source.inventoryServiceAt(ordinal).value
    var shape = AccountFootprintShape(storage: uint64(row.storage), requests: uint64(row.requests))
    template add(target: untyped, amount: uint64) =
      if amount > high(uint64)-target:
        return FootprintAuditResult[CheckedAccountFootprints](status: FootprintAuditError.Overflow,
            service: row.service, ordinal: ordinal)
      target += amount # Never allow byte-sum overflow to become a matching truncated metadata field.
    for j in 0..<row.storage:
      let fact = source.inventoryStorageAt(ordinal, InventoryStorageIndex(uint64(j))).value
      add(shape.storageKeyBytes, fact.keyBytes)
      add(shape.storageValueBytes, fact.valueBytes)
    for j in 0..<row.requests:
      let fact = source.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
      add(shape.requestBytes, uint64(fact.length)) # Current canonical length was validated before inventory capture.
    let calculated = calculateAccountFootprint(shape)
    if calculated.error != AccountFootprintError.None:
      return FootprintAuditResult[CheckedAccountFootprints](status: FootprintAuditError.Overflow,
          service: row.service, ordinal: ordinal) # Preserve E4/E8 representability as a distinct account failure.
    if uint32(calculated.value.items) != uint32(row.metadata.storageItems):
      return FootprintAuditResult[CheckedAccountFootprints](
          status: FootprintAuditError.ItemsMismatch, service: row.service,
          ordinal: ordinal) # Items are compared before octets deterministically.
    if uint64(calculated.value.bytes) != uint64(row.metadata.storageBytes):
      return FootprintAuditResult[CheckedAccountFootprints](
          status: FootprintAuditError.BytesMismatch, service: row.service,
          ordinal: ordinal) # Structurally valid bytes need not obey dependent equations.
  FootprintAuditResult[CheckedAccountFootprints](status: FootprintAuditError.None,
    completed: CheckedAccountFootprints(source: source,
      info: FootprintAuditInfo(services: info.value.services, checks: uint64(
          limits.checks)-remaining)))

proc footprintInfo*(checked: CheckedAccountFootprints): FootprintAuditResult[FootprintAuditInfo] =
  ## Copy completed accounting only from an initialized certificate.
  if checked.source.inventoryInfo.error != StateInventoryError.None:
    return FootprintAuditResult[FootprintAuditInfo](
        status: FootprintAuditError.Uninitialized) # No source certificate.
  FootprintAuditResult[FootprintAuditInfo](status: FootprintAuditError.None,
      completed: checked.info)

proc footprintInventory*(checked: CheckedAccountFootprints): FootprintAuditResult[StateInventory] =
  ## Retain the exact input inventory rather than rebuilding an equal mapping.
  if checked.source.inventoryInfo.error != StateInventoryError.None:
    return FootprintAuditResult[StateInventory](status: FootprintAuditError.Uninitialized) # No source certificate.
  FootprintAuditResult[StateInventory](status: FootprintAuditError.None, completed: checked.source)

proc checkedFootprintAt*(checked: CheckedAccountFootprints,
    ordinal: InventoryServiceIndex): FootprintAuditResult[AccountFootprint] =
  ## Full-width service ordinals select only metadata certified by this source-bound audit.
  if checked.source.inventoryInfo.error != StateInventoryError.None:
    return FootprintAuditResult[AccountFootprint](
        status: FootprintAuditError.Uninitialized) # Default certificate.
  let row = checked.source.inventoryServiceAt(ordinal)
  if row.error != StateInventoryError.None:
    return FootprintAuditResult[AccountFootprint](
        status: FootprintAuditError.InvalidIndex) # Inventory owns narrowing/bounds.
  FootprintAuditResult[AccountFootprint](status: FootprintAuditError.None,
    completed: AccountFootprint(items: row.value.metadata.storageItems,
        bytes: row.value.metadata.storageBytes))
