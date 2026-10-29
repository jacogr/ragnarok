# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Freeze complete actual current logical continuation policy and requalify reconstructed same-identity declarations through existing APIs.
## Exact original/genuine producer provenance never substitutes full actual map matching or grants broader STF/root authority.
import ../refresh/plan as current_refresh_plan
import ../[refresh as current_refresh, request_keys as current_request_keys,
    identities as current_identities]
import ../../supplied/logical_inventory as supplied_logical_inventory
import ../../[inventory, manifest, store]
import ../[profile as current_profile, globals as current_globals, state as current_state,
    logical as current_logical]
import ../../accumulation/current/update as accumulation_current_update
import ../../global_snapshot
import ../../../codec/bounded
type
  CurrentLogicalRefreshLimits* = object ## Component decoders, full logical matching/capture, complete scans and newly retained compact/raw-key arrays have independent ceilings.
    profile*: CurrentProfileLimits
    globals*: GlobalStateLimits
    logical*: SuppliedLogicalLimits
    checks*: ElementLimit
    retainedBytes*: ByteLimit
  CurrentLogicalRefreshInfo* = object ## Exact admitted scan and new retained-array accounting excludes independently bounded globals and already-shared source graphs.
    services*, entries*: int
    checks*, valueBytes*, facts*, rawKeyBytes*, retainedBytes*: uint64
  CurrentLogicalRefreshPlan* = object ## Private frozen reconstruction/source, actual qualified globals and copied policies cannot be paired with replacement targets at execution.
    initialized: bool
    source: CurrentRefreshPlan
    globals: CurrentGlobalSerialization
    limits: CurrentLogicalRefreshLimits
    info: CurrentLogicalRefreshInfo
  LogicalRefreshRefusal* {.pure.} = enum ## Mapping, compact/raw-key capture, whole-scan work and retained arrays remain distinguishable resource policies.
    Mapping, Capture, Scan, Retention
  LogicalRefreshPlanError* {.pure.} = enum ## Invalid original plan, policy refusal and genuine profile/global failure grant no executable prefix.
    Uninitialized, None, InvalidSource, LimitExceeded, ProfileFailure, GlobalsFailure
  LogicalRefreshPlanResult*[T] = object ## Only full admitted actual qualification grants a frozen complete-current continuation plan.
    case status: LogicalRefreshPlanError
    of None:
      completed: T
    of LimitExceeded:
      phase: LogicalRefreshRefusal
    of ProfileFailure:
      profileReason: CurrentProfileResult[DerivedCurrentProfile]
    of GlobalsFailure:
      globalsReason: CurrentGlobalsResult[CurrentGlobalSerialization]
    else:
      discard # No default or failed resource/component stage retains a successful plan.
  LogicalRefreshError* {.pure.} = enum ## Actual reconstruction, complete current matching and raw-key capture retain their original failed results.
    Uninitialized, None, InvalidPlan, RefreshFailure, StateFailure, LogicalFailure
  LogicalRefreshResult* = object ## Complete existing CurrentLogicalState is exposed only after actual whole-map/current/raw-key requalification.
    case status: LogicalRefreshError
    of None:
      completed: CurrentLogicalState
    of RefreshFailure:
      refreshReason: CurrentRefreshResult
    of StateFailure:
      stateReason: CurrentStateResult[CurrentStateSerialization]
    of LogicalFailure:
      logicalReason: CurrentLogicalResult[CurrentLogicalState]
    else:
      discard # No partially reconstructed/matched current source escapes any failure.
func error*[T](outcome: LogicalRefreshPlanResult[T]): LogicalRefreshPlanError =
  ## Observe immutable planning stage without retagging or manufacturing qualification.
  outcome.status
func value*[T](outcome: LogicalRefreshPlanResult[T]): T {.inline, requires: outcome.status ==
    LogicalRefreshPlanError.None.} =
  ## Full successful admission alone exposes plans, fixed quotas or observations.
  outcome.completed
func refusedPhase*[T](outcome: LogicalRefreshPlanResult[T]): LogicalRefreshRefusal {.inline,
    requires: outcome.status == LogicalRefreshPlanError.LimitExceeded.} =
  ## Only an actual resource refusal grants its specific policy boundary.
  outcome.phase
func profileFailure*[T](outcome: LogicalRefreshPlanResult[T]): CurrentProfileResult[
    DerivedCurrentProfile] {.inline, requires: outcome.status ==
    LogicalRefreshPlanError.ProfileFailure.} =
  ## Preserve the original actual current profile/C9 failure.
  outcome.profileReason
func globalsFailure*[T](outcome: LogicalRefreshPlanResult[T]): CurrentGlobalsResult[
    CurrentGlobalSerialization] {.inline, requires: outcome.status ==
    LogicalRefreshPlanError.GlobalsFailure.} =
  ## Preserve original all-chapter missing/malformed/resource distinctions.
  outcome.globalsReason
func error*(outcome: LogicalRefreshResult): LogicalRefreshError =
  ## Observe immutable actual execution stage only.
  outcome.status
func value*(outcome: LogicalRefreshResult): CurrentLogicalState {.inline,
    requires: outcome.status == LogicalRefreshError.None.} =
  ## Existing complete supplied current logical authority still retains the original genuine update/profile and actual full map.
  outcome.completed
func refreshFailure*(outcome: LogicalRefreshResult): CurrentRefreshResult {.inline,
    requires: outcome.status == LogicalRefreshError.RefreshFailure.} =
  ## Retain only the actual failed reconstruction, never a successful mutable output prefix.
  outcome.refreshReason
func stateFailure*(outcome: LogicalRefreshResult): CurrentStateResult[
    CurrentStateSerialization] {.inline, requires: outcome.status ==
    LogicalRefreshError.StateFailure.} =
  ## Preserve genuine failed complete mapping/capture/backend qualification.
  outcome.stateReason
func logicalFailure*(outcome: LogicalRefreshResult): CurrentLogicalResult[
    CurrentLogicalState] {.inline, requires: outcome.status ==
    LogicalRefreshError.LogicalFailure.} =
  ## Preserve the actual failed original-raw-key capture/revalidation result.
  outcome.logicalReason
proc planCurrentLogicalRefresh*(source: CurrentRefreshPlan,
    limits: CurrentLogicalRefreshLimits): LogicalRefreshPlanResult[CurrentLogicalRefreshPlan] =
  ## Preflight all known future matching/capture/scan arrays before any service payload copy, then qualify actual target profile/globals under frozen policies.
  template fail(reason: LogicalRefreshPlanError) =
    return LogicalRefreshPlanResult[CurrentLogicalRefreshPlan](status: reason)
  template refuse(boundary: LogicalRefreshRefusal) =
    return LogicalRefreshPlanResult[CurrentLogicalRefreshPlan](
        status: LogicalRefreshPlanError.LimitExceeded, phase: boundary)
  let keys = source.refreshPlanSource
  if keys.error != CurrentRefreshPlanError.None: fail(LogicalRefreshPlanError.InvalidSource)
  let binding = keys.value.requestKeysSource.value
  let original = binding.identityLogical.value
  let inventory = original.suppliedInventory.value
  let compact = inventory.inventoryInfo.value
  let raw = original.suppliedLogicalInfo.value
  let update = binding.identityUpdate.value
  let target = update.currentUpdateState
  let map = target.commitment
  let matching = limits.logical.inventory.manifest
  if uint64(compact.services) > uint64(matching.services) or uint64(map.entries) > uint64(
      matching.serialized.items) or map.nodes > uint64(matching.serialized.nodes):
    refuse(LogicalRefreshRefusal.Mapping) # Actual complete keys fix composition entry/node shape; profile/current provenance cannot replace this mapping policy.
  if compact.facts > uint64(limits.logical.inventory.facts) or compact.descriptorBytes > min(uint64(
      limits.logical.inventory.bytes), uint64(high(int))):
    refuse(LogicalRefreshRefusal.Capture) # Unchanged service/child identities retain the same native compact descriptors.
  if raw.keys > uint64(limits.logical.keys) or raw.rawKeyBytes > uint64(
      limits.logical.rawKeyBytes) or raw.retainedBytes > min(uint64(limits.logical.bytes), uint64(
      high(int))):
    refuse(LogicalRefreshRefusal.Capture) # Original raw-key count/bytes/extra descriptors cannot grow during same-identity refresh.
  var retained = min(uint64(limits.retainedBytes), uint64(high(int)))
  let retainedBudget = retained
  if compact.descriptorBytes > retained div 2: refuse(LogicalRefreshRefusal.Retention)
  retained-=compact.descriptorBytes*2 # Current compact qualification and raw-key companion each capture one independently bounded compact inventory.
  if raw.retainedBytes > retained: refuse(LogicalRefreshRefusal.Retention)
  retained-=raw.retainedBytes
  var checks = uint64(limits.checks)
  # Admit every complete-map and original raw-key scan before enumerating immutable backing arrays.
  for amount in [uint64(map.entries), uint64(compact.services), raw.keys]:
    if amount > checks: refuse(LogicalRefreshRefusal.Scan)
    checks-=amount # Whole actual-map plus service/raw-key traversal is admitted before any enumeration or component copying.
  var bytes = min(uint64(matching.serialized.totalValueBytes), uint64(high(int)))
  let valueBudget = bytes
  # Cached actual target extents bound all later whole-composition payload copies.
  for i in 0..<map.entries:
    let key = target.keyAt(store.StateEntryIndex(i)).value
    let extent = uint64(target.lookup(key).value.byteLength)
    if extent > uint64(matching.serialized.perValue) or extent > bytes: refuse(
        LogicalRefreshRefusal.Mapping)
    bytes-=extent # Cached immutable extents prove all later composition value copies before any service reconstruction.
  # Unchanged logical storage identities still obey the new frozen per-key matching policy.
  for i in 0..<compact.services:
    let service = InventoryServiceIndex(uint64(i))
    let row = inventory.inventoryServiceAt(service).value
    # Raw-key lengths are fixed original facts; no borrowed key or payload is copied in this scan.
    for j in 0..<row.storage:
      let fact = inventory.inventoryStorageAt(service, InventoryStorageIndex(uint64(j))).value
      if fact.keyBytes > uint64(matching.storageKeyBytes): refuse(LogicalRefreshRefusal.Capture)
  let profile = captureCurrentProfile(update, limits.profile)
  if profile.error != CurrentProfileError.None:
    return LogicalRefreshPlanResult[CurrentLogicalRefreshPlan](
        status: LogicalRefreshPlanError.ProfileFailure, profileReason: profile)
  let globals = qualifyCurrentGlobals(profile.value, limits.globals)
  if globals.error != CurrentGlobalsError.None:
    return LogicalRefreshPlanResult[CurrentLogicalRefreshPlan](
        status: LogicalRefreshPlanError.GlobalsFailure, globalsReason: globals)
  LogicalRefreshPlanResult[CurrentLogicalRefreshPlan](status: LogicalRefreshPlanError.None,
    completed: CurrentLogicalRefreshPlan(initialized: true, source: source, globals: globals.value,
      limits: limits,
      info: CurrentLogicalRefreshInfo(services: compact.services, entries: map.entries,
          checks: uint64(limits.checks)-checks, valueBytes: valueBudget-bytes, facts: compact.facts,
          rawKeyBytes: raw.rawKeyBytes, retainedBytes: retainedBudget-retained)))
proc logicalRefreshPlanSource*(plan: CurrentLogicalRefreshPlan): LogicalRefreshPlanResult[
    CurrentRefreshPlan] =
  ## Retain only the exact frozen reconstruction/original/current source graph.
  if not plan.initialized: return LogicalRefreshPlanResult[CurrentRefreshPlan](
      status: LogicalRefreshPlanError.Uninitialized)
  LogicalRefreshPlanResult[CurrentRefreshPlan](status: LogicalRefreshPlanError.None,
      completed: plan.source)
proc logicalRefreshPlanLimits*(plan: CurrentLogicalRefreshPlan): LogicalRefreshPlanResult[
    CurrentLogicalRefreshLimits] =
  ## Copied policies cannot alter existing plan admission or execution quotas.
  if not plan.initialized: return LogicalRefreshPlanResult[CurrentLogicalRefreshLimits](
      status: LogicalRefreshPlanError.Uninitialized)
  LogicalRefreshPlanResult[CurrentLogicalRefreshLimits](status: LogicalRefreshPlanError.None,
      completed: plan.limits)
proc logicalRefreshPlanInfo*(plan: CurrentLogicalRefreshPlan): LogicalRefreshPlanResult[
    CurrentLogicalRefreshInfo] =
  ## Copy successful scan/retention facts with no mutable source or construction exposure.
  if not plan.initialized: return LogicalRefreshPlanResult[CurrentLogicalRefreshInfo](
      status: LogicalRefreshPlanError.Uninitialized)
  LogicalRefreshPlanResult[CurrentLogicalRefreshInfo](status: LogicalRefreshPlanError.None,
      completed: plan.info)
proc executeCurrentLogicalRefresh*(plan: CurrentLogicalRefreshPlan): LogicalRefreshResult =
  ## Use only frozen policies and actual already-qualified globals, then reproduce the whole actual map through existing current and raw-key constructors.
  if not plan.initialized: return LogicalRefreshResult(status: LogicalRefreshError.InvalidPlan)
  let refreshed = executeCurrentRefresh(plan.source)
  if refreshed.error != CurrentRefreshError.None:
    return LogicalRefreshResult(status: LogicalRefreshError.RefreshFailure,
        refreshReason: refreshed)
  let services = refreshed.value
  let state = qualifyCurrentState(plan.globals, services, plan.limits.logical.inventory)
  if state.error != CurrentStateError.None:
    return LogicalRefreshResult(status: LogicalRefreshError.StateFailure, stateReason: state)
  let logical = captureCurrentLogicalState(state.value, services, plan.limits.logical)
  if logical.error != CurrentLogicalError.None:
    return LogicalRefreshResult(status: LogicalRefreshError.LogicalFailure, logicalReason: logical)
  LogicalRefreshResult(status: LogicalRefreshError.None, completed: logical.value)
