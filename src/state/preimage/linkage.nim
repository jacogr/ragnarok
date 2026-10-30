# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded matching implements the request-membership half of GP accounts eq:preimageconstraints.
## Original immutable inventory provenance binds every hash/length pair without rehashing payloads.
import ../../codec/bounded
import ../../codec/state/[accounts as state_accounts, service_values as state_service_values]
import ../inventory

type
  PreimageLinkageLimits* = object ## Preflight rows, preimages and worst-case pair comparisons independently.
    services*, preimages*, comparisons*: ElementLimit
  PreimageLinkageInfo* = object ## Completed pair comparisons may be fewer than the preflighted worst case.
    preimages*, comparisons*: uint64
  CheckedPreimageLinkage* = object ## All preimages in one original complete inventory have matching request keys.
    source: StateInventory
    info: PreimageLinkageInfo
  PreimageLinkageError* {.pure.} = enum ## Missing association is a semantic failure, independent of resource policy.
    Uninitialized, None, InvalidSource, LimitExceeded, MissingRequest
  PreimageLinkageResult*[T] = object ## No prefix or invented service location is exposed by defaults/refusals.
    case status: PreimageLinkageError
    of None:
      completed: T
    of MissingRequest:
      service: ServiceIndex
      ordinal: InventoryPreimageIndex
    else:
      discard

func error*[T](outcome: PreimageLinkageResult[T]): PreimageLinkageError =
  ## Inspect the immutable failure or success alternative.
  outcome.status

func value*[T](outcome: PreimageLinkageResult[T]): T {.inline,
    requires: outcome.status == PreimageLinkageError.None.} =
  ## Extract only a whole-inventory linkage certificate.
  outcome.completed

func failedService*[T](outcome: PreimageLinkageResult[T]): ServiceIndex {.inline,
    requires: outcome.status == PreimageLinkageError.MissingRequest.} =
  ## Only a genuinely unmatched preimage identifies a service failure.
  outcome.service

func failedPreimage*[T](outcome: PreimageLinkageResult[T]): InventoryPreimageIndex {.inline,
    requires: outcome.status == PreimageLinkageError.MissingRequest.} =
  ## The ordinal remains in the failed service's original preimage order.
  outcome.ordinal

proc auditPreimageLinkage*(source: StateInventory,
    limits: PreimageLinkageLimits): PreimageLinkageResult[CheckedPreimageLinkage] =
  ## Preflight complete worst-case search work before checking any request association.
  template fail(reason: PreimageLinkageError) =
    return PreimageLinkageResult[CheckedPreimageLinkage](status: reason)
  let info = source.inventoryInfo
  if info.error != StateInventoryError.None:
    fail(PreimageLinkageError.InvalidSource) # A default inventory grants no exhaustive absence verdict.
  if uint64(info.value.services) > uint64(limits.services):
    fail(PreimageLinkageError.LimitExceeded) # Row inspection is bounded even when there are no preimages.
  var preimages = uint64(limits.preimages)
  var budget = uint64(limits.comparisons)
  for i in 0..<info.value.services:
    let row = source.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    let count = uint64(row.preimages)
    let requests = uint64(row.requests)
    if count > preimages:
      fail(PreimageLinkageError.LimitExceeded) # Zero-request rows still consume preimage work.
    preimages -= count
    if requests != 0:
      if count > budget div requests:
        fail(PreimageLinkageError.LimitExceeded) # Division proves pair multiplication and aggregate subtraction together.
      budget -= count * requests
  var comparisons = 0'u64
  for i in 0..<info.value.services:
    let index = InventoryServiceIndex(uint64(i))
    let row = source.inventoryServiceAt(index).value
    for j in 0..<row.preimages:
      let ordinal = InventoryPreimageIndex(uint64(j))
      let fact = source.inventoryPreimageAt(index, ordinal).value
      var matched = false
      for k in 0..<row.requests:
        let request = source.inventoryRequestAt(index, InventoryRequestIndex(uint64(k))).value
        comparisons += 1 # Complete worst-case preflight proves every increment within E8.
        if uint64(request.length) == fact.bytes and array[32, byte](request.hash) == array[32,
            byte](fact.hash):
          matched = true
          break # History mode does not participate in the specified request-key membership predicate.
      if not matched:
        return PreimageLinkageResult[CheckedPreimageLinkage](
          status: PreimageLinkageError.MissingRequest,
          service: row.service, ordinal: ordinal) # Never truncate a full-width actual length into the request domain.
  PreimageLinkageResult[CheckedPreimageLinkage](status: PreimageLinkageError.None,
    completed: CheckedPreimageLinkage(source: source,
      info: PreimageLinkageInfo(preimages: uint64(limits.preimages)-preimages,
          comparisons: comparisons)))

proc linkageInfo*(checked: CheckedPreimageLinkage): PreimageLinkageResult[PreimageLinkageInfo] =
  ## Copy completed matching work without exposing mutable certificate state.
  if checked.source.inventoryInfo.error != StateInventoryError.None:
    return PreimageLinkageResult[PreimageLinkageInfo](
        status: PreimageLinkageError.Uninitialized) # Default certificate.
  PreimageLinkageResult[PreimageLinkageInfo](status: PreimageLinkageError.None,
      completed: checked.info)

proc linkageInventory*(checked: CheckedPreimageLinkage): PreimageLinkageResult[StateInventory] =
  ## Retain the exact input owner for later same-source composition of independent predicates.
  if checked.source.inventoryInfo.error != StateInventoryError.None:
    return PreimageLinkageResult[StateInventory](status: PreimageLinkageError.Uninitialized) # Default certificate.
  PreimageLinkageResult[StateInventory](status: PreimageLinkageError.None,
      completed: checked.source)
