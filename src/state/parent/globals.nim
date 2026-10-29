# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Qualify all sixteen globals on one original selected configured parent without substituting its map/profile/view.
import ./profile as parent_profile
import ../global_snapshot
type
  SelectedParentGlobals* = object ## Private original profile/view and all-global evidence are distinct from transition completion.
    initialized: bool
    profile: SelectedParentProfile
    globals: ValidatedGlobalState
  ParentGlobalsError* {.pure.} = enum ## Invalid/default selection and genuine global serialization failure preserve distinct stages.
    Uninitialized, None, InvalidProfile, GlobalFailure
  ParentGlobalsResult*[T] = object ## Private alternatives retain no usable prefix after failed global qualification.
    case status: ParentGlobalsError
    of None:
      completed: T
    of GlobalFailure:
      globalReason: GlobalStateResult[ValidatedGlobalState]
    else:
      discard # Default/invalid input grants no configured parent or complete global authority.
func error*[T](outcome: ParentGlobalsResult[T]): ParentGlobalsError =
  ## Observe selected immutable alternatives only.
  outcome.status
func value*[T](outcome: ParentGlobalsResult[T]): T {.inline, requires: outcome.status ==
    ParentGlobalsError.None.} =
  ## Extract only successful original-source evidence.
  outcome.completed
func globalFailure*[T](outcome: ParentGlobalsResult[T]): GlobalStateResult[
    ValidatedGlobalState] {.inline, requires: outcome.status == ParentGlobalsError.GlobalFailure.} =
  ## Preserve only the genuinely failed original global result, including guarded chapter/codec/resource reasons.
  outcome.globalReason
proc qualifyParentGlobals*(source: SelectedParentProfile,
    limits: GlobalStateLimits): ParentGlobalsResult[SelectedParentGlobals] =
  ## Preflight every required original cached chapter extent before existing exact codecs allocate/copy values.
  let context = source.parentContext
  if context.error != ParentProfileError.None:
    return ParentGlobalsResult[SelectedParentGlobals](status: ParentGlobalsError.InvalidProfile)
  let globals = validateGlobalState(context.value.state, source.parentStateProfile.value, limits)
  if globals.error != GlobalStateError.None:
    return ParentGlobalsResult[SelectedParentGlobals](status: ParentGlobalsError.GlobalFailure,
        globalReason: globals) # No stripped, rebuilt or equal-root map can satisfy the original selected parent qualification.
  ParentGlobalsResult[SelectedParentGlobals](status: ParentGlobalsError.None,
      completed: SelectedParentGlobals(initialized: true, profile: source, globals: globals.value))
proc parentGlobalsProfile*(source: SelectedParentGlobals): ParentGlobalsResult[
    SelectedParentProfile] =
  ## Retain the exact original selection, ordered history, full Parameters and explicit finality state.
  if not source.initialized:
    return ParentGlobalsResult[SelectedParentProfile](status: ParentGlobalsError.Uninitialized)
  ParentGlobalsResult[SelectedParentProfile](status: ParentGlobalsError.None,
      completed: source.profile)
proc parentGlobals*(source: SelectedParentGlobals): ParentGlobalsResult[ValidatedGlobalState] =
  ## Retain all sixteen qualified globals on the original physical source without claiming service serialization.
  if not source.initialized:
    return ParentGlobalsResult[ValidatedGlobalState](status: ParentGlobalsError.Uninitialized)
  ParentGlobalsResult[ValidatedGlobalState](status: ParentGlobalsError.None,
      completed: source.globals)
