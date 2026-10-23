# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Capture a complete supplied configured logical seed from the actual application chain on the stable host.
import ./chain
import ../state/[parent_profile, parent_globals, parent_logical, global_snapshot, supplied_logical_inventory]
import ../codec/state_composition
type
  LogicalSeedLimits* = object ## Selected-view retention, all globals and supplied logical arrays retain independent ceilings.
    profile*: ParentProfileLimits
    globals*: GlobalStateLimits
    logical*: SuppliedLogicalLimits
  LogicalSeedError* {.pure.} = enum ## Original selected profile, global codecs and complete declaration matching stay distinct.
    Uninitialized, None, ProfileFailure, GlobalsFailure, LogicalFailure
  LogicalSeedResult* = object ## No partial source owner escapes a failed stage.
    case status: LogicalSeedError
    of None: completed: SelectedLogicalParent
    of ProfileFailure: profileReason: ParentProfileResult[SelectedParentProfile]
    of GlobalsFailure: globalsReason: ParentGlobalsResult[SelectedParentGlobals]
    of LogicalFailure: logicalReason: ParentLogicalResult[SelectedLogicalParent]
    else: discard             # Defaults grant neither selected state nor logical inventory.
func error*(outcome: LogicalSeedResult): LogicalSeedError =
  ## Observe the selected immutable stage without granting its payload.
  outcome.status
func value*(outcome: LogicalSeedResult): SelectedLogicalParent {.inline, requires: outcome.status ==
    LogicalSeedError.None.} =
  ## Retain only fully matched original selected logical evidence.
  outcome.completed
func profileFailure*(outcome: LogicalSeedResult): ParentProfileResult[
    SelectedParentProfile] {.inline, requires: outcome.status == LogicalSeedError.ProfileFailure.} =
  ## Preserve missing C9, malformed roster, missing head and retention failures.
  outcome.profileReason
func globalsFailure*(outcome: LogicalSeedResult): ParentGlobalsResult[
    SelectedParentGlobals] {.inline, requires: outcome.status == LogicalSeedError.GlobalsFailure.} =
  ## Preserve exact original all-global codec and resource failures.
  outcome.globalsReason
func logicalFailure*(outcome: LogicalSeedResult): ParentLogicalResult[
    SelectedLogicalParent] {.inline, requires: outcome.status == LogicalSeedError.LogicalFailure.} =
  ## Preserve complete map matching and raw-key capture refusals.
  outcome.logicalReason
proc captureLogicalSeed*(chain: ApplicationChain, services: openArray[StateService],
    limits: LogicalSeedLimits): LogicalSeedResult =
  ## Match stable borrowed declarations against the original whole selected view; host execution must be outside every native graph lease.
  let profile = captureParentProfile(chain.chainView, limits.profile)
  if profile.error != ParentProfileError.None:
    return LogicalSeedResult(status: LogicalSeedError.ProfileFailure, profileReason: profile)
  let globals = qualifyParentGlobals(profile.value, limits.globals)
  if globals.error != ParentGlobalsError.None:
    return LogicalSeedResult(status: LogicalSeedError.GlobalsFailure, globalsReason: globals)
  let logical = captureLogicalParent(globals.value, services, limits.logical)
  if logical.error != ParentLogicalError.None:
    return LogicalSeedResult(status: LogicalSeedError.LogicalFailure, logicalReason: logical)
  LogicalSeedResult(status: LogicalSeedError.None, completed: logical.value)
