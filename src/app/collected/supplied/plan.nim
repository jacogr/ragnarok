# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Freeze the genuine collected target and explicit policies for later complete supplied successor qualification.
import ../../[chain, preparation_worker]
import ../update as collected_update
import ../../../state/current/[profile as current_profile, globals as current_globals]
import ../../../state/accumulation/current/update as accumulation_current_update
import ../../../state/global_snapshot
import ../../../state/supplied/logical_inventory as supplied_logical_inventory
type
  CollectedSuppliedLimits* = object ## Profile/global decoding and complete supplied logical matching retain separate quotas.
    profile*: CurrentProfileLimits
    globals*: GlobalStateLimits
    logical*: SuppliedLogicalLimits
  CollectedSuppliedPlan* = object ## Immutable target and copied policies cannot be paired with caller-selected maps or parameter tuples.
    initialized: bool
    update: PreparedCurrentChainUpdate
    globals: CurrentGlobalSerialization
    limits: CollectedSuppliedLimits
  CollectedSuppliedPlanError* {.pure.} = enum ## Actual receipt admission and original component causes remain distinct.
    Uninitialized, None, AdmissionFailure, ProfileFailure, GlobalsFailure
  CollectedSuppliedPlanResult*[T] = object ## Failed/default alternatives retain no executable target prefix.
    case status: CollectedSuppliedPlanError
    of None: completed: T
    of AdmissionFailure: admissionReason: CollectedUpdateResult
    of ProfileFailure: profileReason: CurrentProfileResult[DerivedCurrentProfile]
    of GlobalsFailure: globalsReason: CurrentGlobalsResult[CurrentGlobalSerialization]
    else: discard # Defaults have no plan, policies or source authority.

func error*[T](outcome: CollectedSuppliedPlanResult[T]): CollectedSuppliedPlanError =
  ## Observe the selected immutable stage only.
  outcome.status

func value*[T](outcome: CollectedSuppliedPlanResult[T]): T {.inline,
    requires: outcome.status == CollectedSuppliedPlanError.None.} =
  ## Expose only complete original-source observations and frozen policies.
  outcome.completed

func admissionFailure*[T](outcome: CollectedSuppliedPlanResult[T]): CollectedUpdateResult {.inline,
    requires: outcome.status == CollectedSuppliedPlanError.AdmissionFailure.} =
  ## Preserve actual receipt lifecycle, typed preparation refusal and stale canonical selection.
  outcome.admissionReason

func profileFailure*[T](outcome: CollectedSuppliedPlanResult[T]): CurrentProfileResult[
    DerivedCurrentProfile] {.inline,

requires: outcome.status == CollectedSuppliedPlanError.ProfileFailure.} =
  ## Preserve exact actual current/C9 profile and resource failures.
  outcome.profileReason

func globalsFailure*[T](outcome: CollectedSuppliedPlanResult[T]): CurrentGlobalsResult[
    CurrentGlobalSerialization] {.inline,

requires: outcome.status == CollectedSuppliedPlanError.GlobalsFailure.} =
  ## Preserve all-global missing, malformed and bounded codec causes.
  outcome.globalsReason

proc planCollectedSupplied*(chain: ApplicationChain, receipt: PreparationCompletion,
    limits: CollectedSuppliedLimits): CollectedSuppliedPlanResult[CollectedSuppliedPlan] =
  ## Caller holds the host ARC gate open; capture only actual qualified globals, without copying or inferring supplied namespaces.
  let admitted = captureCollectedUpdate(chain, receipt)
  if admitted.error != CollectedUpdateError.None:
    return CollectedSuppliedPlanResult[CollectedSuppliedPlan](
      status: CollectedSuppliedPlanError.AdmissionFailure,
      admissionReason: admitted)
  let profile = captureCurrentProfile(admitted.value, limits.profile)
  if profile.error != CurrentProfileError.None:
    return CollectedSuppliedPlanResult[CollectedSuppliedPlan](
      status: CollectedSuppliedPlanError.ProfileFailure,
      profileReason: profile)
  let globals = qualifyCurrentGlobals(profile.value, limits.globals)
  if globals.error != CurrentGlobalsError.None:
    return CollectedSuppliedPlanResult[CollectedSuppliedPlan](
      status: CollectedSuppliedPlanError.GlobalsFailure,
      globalsReason: globals)
  CollectedSuppliedPlanResult[CollectedSuppliedPlan](status: CollectedSuppliedPlanError.None,
    completed: CollectedSuppliedPlan(initialized: true, update: admitted.value,
        globals: globals.value, limits: limits))

proc collectedSuppliedUpdate*(plan: CollectedSuppliedPlan): CollectedSuppliedPlanResult[
    PreparedCurrentChainUpdate] =
  ## Retain only the actual admitted target; no map or detached header replacement is accepted.
  if not plan.initialized:
    return CollectedSuppliedPlanResult[PreparedCurrentChainUpdate](
        status: CollectedSuppliedPlanError.Uninitialized)
  CollectedSuppliedPlanResult[PreparedCurrentChainUpdate](status: CollectedSuppliedPlanError.None,
      completed: plan.update)

proc collectedSuppliedGlobals*(plan: CollectedSuppliedPlan): CollectedSuppliedPlanResult[
    CurrentGlobalSerialization] =
  ## Retain exact target profile/global provenance without re-decoding or complete-service claims.
  if not plan.initialized:
    return CollectedSuppliedPlanResult[CurrentGlobalSerialization](
        status: CollectedSuppliedPlanError.Uninitialized)
  CollectedSuppliedPlanResult[CurrentGlobalSerialization](status: CollectedSuppliedPlanError.None,
      completed: plan.globals)

proc collectedSuppliedLimits*(plan: CollectedSuppliedPlan): CollectedSuppliedPlanResult[
    CollectedSuppliedLimits] =
  ## Return a detached fixed policy copy; changing it cannot alter this plan.
  if not plan.initialized:
    return CollectedSuppliedPlanResult[CollectedSuppliedLimits](
        status: CollectedSuppliedPlanError.Uninitialized)
  CollectedSuppliedPlanResult[CollectedSuppliedLimits](status: CollectedSuppliedPlanError.None,
      completed: plan.limits)
