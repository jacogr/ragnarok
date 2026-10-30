# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Select metadata and every declared service namespace from original logical provenance under whole key/work admission.
import ../../state/current/logical as current_logical
import ../../state/supplied/logical_inventory as supplied_logical_inventory
import ../../state/inventory
import ../../state/proof/plan as proof_plan
import ../../codec/bounded
import ../../codec/state/[layout as state_layout, requests as state_requests]
type
  LogicalServiceProofLimits* = object ## Full service traversal, total selectors, request hashes and scratch/retained key arrays have separate ceilings.
    services*, keys*, requests*: ElementLimit
    bytes*: ByteLimit
  LogicalServiceProofInfo* = object ## Coverage describes this explicitly selected service, not complete-map or root-trust authority.
    service*: ServiceIndex
    keys*, requests*: int
  LogicalServiceProof* = object ## The original complete logical source and all selected keys cannot be cross-paired or edited.
    initialized: bool
    source: CurrentLogicalState
    keys: StateProofPlan
    info: LogicalServiceProofInfo
  LogicalServiceProofError* {.pure.} = enum ## Invalid source, bounded traversal/copy, genuine absence and mandatory hashing failures remain distinct.
    Uninitialized, None, InvalidLogical, LimitExceeded, NoService, KeyFailure, PlanFailure
  LogicalServiceProofResult*[T] = object ## Refusals never expose a selected prefix or a default root/plan.
    case status: LogicalServiceProofError
    of None: completed: T
    of KeyFailure: keyReason: RequestError
    of PlanFailure: planReason: ProofPlanError
    else: discard # Missing source/service and quota failures contain no key owner.

func error*[T](outcome: LogicalServiceProofResult[T]): LogicalServiceProofError =
  ## Observe immutable selected stages only.
  outcome.status

func value*[T](outcome: LogicalServiceProofResult[T]): T {.inline, requires: outcome.status ==
    LogicalServiceProofError.None.} =
  ## Extract only complete source-bound namespace selection or fixed observations.
  outcome.completed

func requestError*[T](outcome: LogicalServiceProofResult[T]): RequestError {.inline,
    requires: outcome.status == LogicalServiceProofError.KeyFailure.} =
  ## Preserve the exact request-key derivation failure without a default physical key.
  outcome.keyReason

func planError*[T](outcome: LogicalServiceProofResult[T]): ProofPlanError {.inline,
    requires: outcome.status == LogicalServiceProofError.PlanFailure.} =
  ## Preserve the generic immutable proof selector's actual refusal.
  outcome.planReason

proc planLogicalServiceProof*(source: CurrentLogicalState, service: ServiceIndex,
    limits: LogicalServiceProofLimits): LogicalServiceProofResult[LogicalServiceProof] =
  ## Admit complete traversal and both temporary/retained arrays before deriving any request key or allocating selectors.
  template fail(reason: LogicalServiceProofError) =
    return LogicalServiceProofResult[LogicalServiceProof](status: reason)
  let logical = source.currentLogicalInventory
  if logical.error != CurrentLogicalError.None: fail(LogicalServiceProofError.InvalidLogical)
  let inventory = logical.value.suppliedInventory.value
  let count = inventory.inventoryInfo.value.services
  if uint64(count) > uint64(limits.services): fail(LogicalServiceProofError.LimitExceeded)
  var selected = -1
  for i in 0..<count:
    if inventory.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value.service == service:
      selected = i
      break # Captured complete inventories have unique service identities.
  if selected < 0: fail(LogicalServiceProofError.NoService)
  let ordinal = InventoryServiceIndex(uint64(selected))
  let row = inventory.inventoryServiceAt(ordinal).value
  let budget = min(uint64(limits.keys), uint64(high(int)))
  var remaining = budget
  template charge(amount: int) =
    block:
      let extent = uint64(amount)
      if extent > remaining: fail(LogicalServiceProofError.LimitExceeded)
      remaining -= extent # Subtraction proves total selector addition and later native narrowing.
  charge(1)
  charge(row.storage)
  charge(row.preimages)
  charge(row.requests)
  let total = budget-remaining
  let slots = min(uint64(limits.bytes), uint64(high(int))) div uint64(sizeof(StateKey))
  if uint64(row.requests) > uint64(limits.requests) or total > slots div 2:
    fail(LogicalServiceProofError.LimitExceeded)
  if total div 2 > slots-total*2:
    fail(LogicalServiceProofError.LimitExceeded) # Input, retained keys and pinned merge-sort scratch all fit before allocation.
  var keys = newSeq[StateKey](int(total))
  keys[0] = chapterServiceKey(StateChapter(255), service)
  var next = 1
  for j in 0..<row.storage:
    keys[next] = inventory.inventoryStorageAt(ordinal, InventoryStorageIndex(uint64(j))).value.key
    inc next
  for j in 0..<row.preimages:
    keys[next] = inventory.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value.key
    inc next
  for j in 0..<row.requests:
    let request = inventory.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
    let key = serviceRequestKey(service, request.hash, request.length, ByteLimit(32))
    if key.error != RequestError.None:
      return LogicalServiceProofResult[LogicalServiceProof](
          status: LogicalServiceProofError.KeyFailure, keyReason: key.error)
    keys[next] = key.value
    inc next
  let plan = captureStateProofPlan(keys, limits.keys)
  if plan.error != ProofPlanError.None:
    return LogicalServiceProofResult[LogicalServiceProof](
        status: LogicalServiceProofError.PlanFailure, planReason: plan.error)
  LogicalServiceProofResult[LogicalServiceProof](status: LogicalServiceProofError.None,
    completed: LogicalServiceProof(initialized: true, source: source, keys: plan.value,
      info: LogicalServiceProofInfo(service: service, keys: plan.value.len,
          requests: row.requests)))

proc logicalServiceProofSource*(source: LogicalServiceProof): LogicalServiceProofResult[
    CurrentLogicalState] =
  ## Retain the exact original logical source for existing bounded query capture and managed submission.
  if not source.initialized: return LogicalServiceProofResult[CurrentLogicalState](
      status: LogicalServiceProofError.InvalidLogical)
  LogicalServiceProofResult[CurrentLogicalState](status: LogicalServiceProofError.None,
      completed: source.source)

proc logicalServiceProofKeys*(source: LogicalServiceProof): LogicalServiceProofResult[
    StateProofPlan] =
  ## Retain only this source-bound complete namespace selector; no mutable key array is exposed.
  if not source.initialized: return LogicalServiceProofResult[StateProofPlan](
      status: LogicalServiceProofError.InvalidLogical)
  LogicalServiceProofResult[StateProofPlan](status: LogicalServiceProofError.None,
      completed: source.keys)

proc logicalServiceProofInfo*(source: LogicalServiceProof): LogicalServiceProofResult[
    LogicalServiceProofInfo] =
  ## Copy fixed service/key/hash-work coverage without changing trust or provenance.
  if not source.initialized: return LogicalServiceProofResult[LogicalServiceProofInfo](
      status: LogicalServiceProofError.InvalidLogical)
  LogicalServiceProofResult[LogicalServiceProofInfo](status: LogicalServiceProofError.None,
      completed: source.info)
