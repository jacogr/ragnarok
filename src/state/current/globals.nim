# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind exact all-chapter serialization to one genuine current producer and its derived retained profile.
## Global framing remains separate from complete service matching, semantic validity, root discovery and STF parity.
import ./profile as current_profile
import ../accumulation/current/update as accumulation_current_update
import ../global_snapshot
type
  CurrentGlobalSerialization* = object ## Private same-source owners prevent a foreign profile or equal-root map substitution.
    initialized: bool
    profile: DerivedCurrentProfile
    globals: ValidatedGlobalState
  CurrentGlobalsError* {.pure.} = enum ## Default profile and genuinely failed global validation expose no qualified prefix.
    Uninitialized, None, InvalidProfile, GlobalFailure
  CurrentGlobalsResult*[T] = object ## Private alternatives preserve exact nested missing/malformed/resource reasons.
    case status: CurrentGlobalsError
    of None:
      completed: T
    of GlobalFailure:
      globalReason: GlobalStateResult[ValidatedGlobalState]
    else:
      discard # No default/failed result grants qualified ownership.

func error*[T](outcome: CurrentGlobalsResult[T]): CurrentGlobalsError =
  ## Observe the selected immutable reason.
  outcome.status

func value*[T](outcome: CurrentGlobalsResult[T]): T {.inline, requires: outcome.status ==
    CurrentGlobalsError.None.} =
  ## Only complete initialized qualification authorizes extraction.
  outcome.completed

func globalFailure*[T](outcome: CurrentGlobalsResult[T]): GlobalStateResult[
    ValidatedGlobalState] {.inline, requires: outcome.status ==
    CurrentGlobalsError.GlobalFailure.} =
  ## Preserve only the original genuinely failed global result and its guarded nested reason.
  outcome.globalReason

proc qualifyCurrentGlobals*(profile: DerivedCurrentProfile,
    limits: GlobalStateLimits): CurrentGlobalsResult[CurrentGlobalSerialization] =
  ## Admit all sixteen cached extents before whole-global value copies; prior C9 projection had its own independent limits.
  let source = profile.derivedUpdate
  if source.error != CurrentProfileError.None:
    return CurrentGlobalsResult[CurrentGlobalSerialization](
        status: CurrentGlobalsError.InvalidProfile)
  let globals = validateGlobalState(source.value.currentUpdateState,
      profile.derivedStateProfile.value, limits)
  if globals.error != GlobalStateError.None:
    return CurrentGlobalsResult[CurrentGlobalSerialization](
      status: CurrentGlobalsError.GlobalFailure,
      globalReason: globals) # Never substitute a different producer/map/profile to satisfy framing.
  CurrentGlobalsResult[CurrentGlobalSerialization](status: CurrentGlobalsError.None,
    completed: CurrentGlobalSerialization(initialized: true, profile: profile,
        globals: globals.value))

proc qualifiedCurrentProfile*(source: CurrentGlobalSerialization): CurrentGlobalsResult[
    DerivedCurrentProfile] =
  ## Return the exact original projection, including the full parameter tuple and producer identity.
  if not source.initialized:
    return CurrentGlobalsResult[DerivedCurrentProfile](status: CurrentGlobalsError.Uninitialized)
  CurrentGlobalsResult[DerivedCurrentProfile](status: CurrentGlobalsError.None,
      completed: source.profile)

proc qualifiedGlobals*(source: CurrentGlobalSerialization): CurrentGlobalsResult[
    ValidatedGlobalState] =
  ## Retain the original all-chapter source without claiming validation of remaining service rows.
  if not source.initialized:
    return CurrentGlobalsResult[ValidatedGlobalState](status: CurrentGlobalsError.Uninitialized)
  CurrentGlobalsResult[ValidatedGlobalState](status: CurrentGlobalsError.None,
      completed: source.globals)
