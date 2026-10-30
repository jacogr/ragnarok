# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable complete-source account audit plans preflight every predicate policy before copying or hashing payloads.
## Planning grants bounded execution authority only, never successful account invariants or trusted-root authority.
import ../../../codec/bounded
import ../../[inventory, footprint_audit]
import ../../preimage/[content as preimage_content, linkage as preimage_linkage]

type
  AccountAuditLimits* = object ## Count both row passes and preimage-fact inspections independently from each predicate's own policy.
    planning*: ElementLimit
    footprints*: FootprintAuditLimits
    content*: PreimageContentLimits
    linkage*: PreimageLinkageLimits
  AccountAuditPlanInfo* = object ## Exact planned work and worst-case matching observations contain no validity claim.
    services*: int
    planningChecks*, footprintChecks*, preimages*, contentBytes*, comparisonCeiling*: uint64
  AccountAuditRefusal* {.pure.} = enum ## Every budget refusal names its actual resource-policy boundary.
    Planning, Footprints, Content, Linkage
  StateAccountAuditPlan* = object ## Private original inventory and fixed policies prevent source or quota substitution after capture.
    source: StateInventory
    limits: AccountAuditLimits
    info: AccountAuditPlanInfo
  AccountAuditPlanError* {.pure.} = enum ## Default/invalid provenance and typed policy refusal grant no executable prefix.
    Uninitialized, None, InvalidSource, LimitExceeded
  AccountAuditPlanResult*[T] = object ## Only successful whole-source preflight exposes a frozen plan.
    case status: AccountAuditPlanError
    of None:
      completed: T
    of LimitExceeded:
      phase: AccountAuditRefusal
    else:
      discard

func error*[T](outcome: AccountAuditPlanResult[T]): AccountAuditPlanError =
  ## Inspect the immutable selected alternative.
  outcome.status

func value*[T](outcome: AccountAuditPlanResult[T]): T {.inline,
    requires: outcome.status == AccountAuditPlanError.None.} =
  ## No failed/default plan grants a source-bearing executable owner.
  outcome.completed

func refusedPhase*[T](outcome: AccountAuditPlanResult[T]): AccountAuditRefusal {.inline,
    requires: outcome.status == AccountAuditPlanError.LimitExceeded.} =
  ## Defaults and invalid sources cannot invent a resource boundary.
  outcome.phase

proc planAccountAudit*(source: StateInventory,
    limits: AccountAuditLimits): AccountAuditPlanResult[StateAccountAuditPlan] =
  ## Two bounded row passes charge all fact traversal and predicate work before payload access or primitive calls.
  template refuse(boundary: AccountAuditRefusal) =
    return AccountAuditPlanResult[StateAccountAuditPlan](
        status: AccountAuditPlanError.LimitExceeded, phase: boundary)
  let info = source.inventoryInfo
  if info.error != StateInventoryError.None:
    return AccountAuditPlanResult[StateAccountAuditPlan](
        status: AccountAuditPlanError.InvalidSource) # Only an exact complete capture supports whole-source planning.
  let count = uint64(info.value.services)
  if count > uint64(limits.footprints.services):
    refuse(AccountAuditRefusal.Footprints) # Bound row enumeration under every independent consumer policy.
  if count > uint64(limits.content.services):
    refuse(AccountAuditRefusal.Content)
  if count > uint64(limits.linkage.services):
    refuse(AccountAuditRefusal.Linkage)
  var planning = uint64(limits.planning)
  if count > planning div 2:
    refuse(AccountAuditRefusal.Planning) # Prove both row-pass charges before multiplication or traversal.
  planning -= count * 2
  var footprint = uint64(limits.footprints.checks)
  if count > footprint:
    refuse(AccountAuditRefusal.Footprints)
  footprint -= count
  var content = uint64(limits.content.preimages)
  var linkage = uint64(limits.linkage.preimages)
  var comparisons = uint64(limits.linkage.comparisons)
  for i in 0..<info.value.services:
    let row = source.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    for amount in [uint64(row.storage), uint64(row.requests)]:
      if amount > footprint:
        refuse(AccountAuditRefusal.Footprints)
      footprint -= amount # Count all dependent facts, including empty values.
    let preimages = uint64(row.preimages)
    if preimages > planning:
      refuse(AccountAuditRefusal.Planning)
    planning -= preimages
    if preimages > content:
      refuse(AccountAuditRefusal.Content)
    content -= preimages
    if preimages > linkage:
      refuse(AccountAuditRefusal.Linkage)
    linkage -= preimages
    let requests = uint64(row.requests)
    if requests != 0:
      if preimages > comparisons div requests:
        refuse(AccountAuditRefusal.Linkage)
      comparisons -= preimages * requests # Division proves worst-case comparison multiplication and aggregate subtraction.
  var bytes = uint64(limits.content.totalBytes)
  for i in 0..<info.value.services:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = source.inventoryServiceAt(ordinal).value
    for j in 0..<row.preimages:
      let fact = source.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value
      if fact.bytes > uint64(limits.content.perValue) or fact.bytes > bytes:
        refuse(AccountAuditRefusal.Content) # Only fixed captured extents are read; payload bytes remain untouched.
      bytes -= fact.bytes
  AccountAuditPlanResult[StateAccountAuditPlan](status: AccountAuditPlanError.None,
    completed: StateAccountAuditPlan(source: source, limits: limits,
      info: AccountAuditPlanInfo(services: info.value.services,
        planningChecks: uint64(limits.planning)-planning, footprintChecks: uint64(
            limits.footprints.checks)-footprint,
        preimages: uint64(limits.content.preimages)-content, contentBytes: uint64(
            limits.content.totalBytes)-bytes,
        comparisonCeiling: uint64(limits.linkage.comparisons)-comparisons)))

proc accountPlanInfo*(plan: StateAccountAuditPlan): AccountAuditPlanResult[AccountAuditPlanInfo] =
  ## Copy or retain only the original immutable completed plan info.
  if plan.source.inventoryInfo.error != StateInventoryError.None:
    return AccountAuditPlanResult[AccountAuditPlanInfo](
        status: AccountAuditPlanError.Uninitialized) # Default is not executable empty planning authority.
  AccountAuditPlanResult[AccountAuditPlanInfo](status: AccountAuditPlanError.None,
      completed: plan.info)

proc accountPlanInventory*(plan: StateAccountAuditPlan): AccountAuditPlanResult[StateInventory] =
  ## Copy or retain only the original immutable completed plan source.
  if plan.source.inventoryInfo.error != StateInventoryError.None:
    return AccountAuditPlanResult[StateInventory](
        status: AccountAuditPlanError.Uninitialized) # Default is not executable empty planning authority.
  AccountAuditPlanResult[StateInventory](status: AccountAuditPlanError.None, completed: plan.source)

proc accountPlanLimits*(plan: StateAccountAuditPlan): AccountAuditPlanResult[AccountAuditLimits] =
  ## Copy or retain only the original immutable completed plan limits.
  if plan.source.inventoryInfo.error != StateInventoryError.None:
    return AccountAuditPlanResult[AccountAuditLimits](
        status: AccountAuditPlanError.Uninitialized) # Default is not executable empty planning authority.
  AccountAuditPlanResult[AccountAuditLimits](status: AccountAuditPlanError.None,
      completed: plan.limits)
