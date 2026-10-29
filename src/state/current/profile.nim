# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive structural state cardinalities and retain full parameters from one genuine current update.
## Bounded exact C9 decoding never falls back to the current population or substitutes an equal-root map.
import ../accumulation/current/update as accumulation_current_update
import ../store
import ../../chain/[genesis, parameters]
import ../../codec/bounded
import ../../codec/state/[layout as state_layout, safrole as state_safrole,
    composition as state_composition]
import ../../codec/[assurances, header]
type
  CurrentProfileLimits* = object ## Previous-roster bytes/items are preflighted independently of later whole-global validation.
    validators*: ElementLimit
    bytes*: ByteLimit
  DerivedCurrentProfile* = object ## Private fixed observations retain the exact original producer graph.
    initialized: bool
    source: PreparedCurrentChainUpdate
    profile: StateProfile
    parameters: Parameters
  CurrentProfileError* {.pure.} = enum ## Missing complete-state data, malformed roster, policy refusal and default provenance remain distinct.
    Uninitialized, None, InvalidUpdate, MissingPrevious, LimitExceeded, PreviousFailure,
      TrailingPrevious, InvalidProfile
  CurrentProfileResult*[T] = object ## Only complete projection exposes fixed cardinalities/parameters or original producer provenance.
    case status: CurrentProfileError
    of None:
      completed: T
    of PreviousFailure:
      previousReason: StateComponentError
    else:
      discard # No failed/default result contains a successful prefix.
func error*[T](outcome: CurrentProfileResult[T]): CurrentProfileError =
  ## Observe the immutable selected reason.
  outcome.status
func value*[T](outcome: CurrentProfileResult[T]): T {.inline, requires: outcome.status ==
    CurrentProfileError.None.} =
  ## Only complete initialized projection authorizes extraction.
  outcome.completed
func previousError*[T](outcome: CurrentProfileResult[T]): StateComponentError {.inline,
    requires: outcome.status == CurrentProfileError.PreviousFailure.} =
  ## Preserve only the actual previous-roster decoder refusal.
  outcome.previousReason
proc captureCurrentProfile*(source: PreparedCurrentChainUpdate,
    limits: CurrentProfileLimits): CurrentProfileResult[DerivedCurrentProfile] =
  ## Read only the stable host-owned update before enqueue or after collection/join, including alias retirement.
  if not source.ready:
    return CurrentProfileResult[DerivedCurrentProfile](status: CurrentProfileError.InvalidUpdate)
  let child = source.currentUpdateChildContext
  let cores = CoreCount(child.parameters.get(coreCount))
  let previous = source.currentUpdateState.lookup(chapterKey(StateChapter(9)))
  if previous.error == StateStoreError.MissingKey:
    return CurrentProfileResult[DerivedCurrentProfile](status: CurrentProfileError.MissingPrevious)
  if previous.error != StateStoreError.None:
    return CurrentProfileResult[DerivedCurrentProfile](status: CurrentProfileError.InvalidUpdate)
  if uint64(previous.value.byteLength) > uint64(limits.bytes):
    return CurrentProfileResult[DerivedCurrentProfile](
        status: CurrentProfileError.LimitExceeded) # Cached extent refuses before value copy or typed roster allocation.
  let input = previous.value.bytes
  let decoded = decodeStateValidators(input, ValidatorStateConfig(cores: cores,
    validators: limits.validators, maxBytes: limits.bytes))
  if decoded.error != StateComponentError.None:
    return CurrentProfileResult[DerivedCurrentProfile](status: CurrentProfileError.PreviousFailure,
        previousReason: decoded.error)
  if decoded.value.consumed != input.len:
    return CurrentProfileResult[DerivedCurrentProfile](status: CurrentProfileError.TrailingPrevious)
  let count = decoded.value.value.validatorCount
  if count.error != StateComponentError.None:
    return CurrentProfileResult[DerivedCurrentProfile](status: CurrentProfileError.PreviousFailure,
        previousReason: count.error)
  if count.value < 0:
    return CurrentProfileResult[DerivedCurrentProfile](
        status: CurrentProfileError.InvalidProfile) # Prove signed-to-unsigned conversion before construction.
  let profile = StateProfile(cores: cores, current: child.validators,
    previous: ValidatorCount(uint64(count.value)), epochSlots: EpochSlots(child.parameters.get(epochPeriod)))
  if not profile.valid:
    return CurrentProfileResult[DerivedCurrentProfile](status: CurrentProfileError.InvalidProfile)
  CurrentProfileResult[DerivedCurrentProfile](status: CurrentProfileError.None,
    completed: DerivedCurrentProfile(initialized: true, source: source, profile: profile,
        parameters: child.parameters))
proc derivedStateProfile*(captured: DerivedCurrentProfile): CurrentProfileResult[StateProfile] =
  ## Copy structural cardinalities only from an initialized same-source projection.
  if not captured.initialized:
    return CurrentProfileResult[StateProfile](status: CurrentProfileError.Uninitialized)
  CurrentProfileResult[StateProfile](status: CurrentProfileError.None, completed: captured.profile)
proc derivedParameters*(captured: DerivedCurrentProfile): CurrentProfileResult[Parameters] =
  ## Retain the full original tuple separately; four cardinalities cannot replace execution/economic configuration.
  if not captured.initialized:
    return CurrentProfileResult[Parameters](status: CurrentProfileError.Uninitialized)
  CurrentProfileResult[Parameters](status: CurrentProfileError.None, completed: captured.parameters)
proc derivedUpdate*(captured: DerivedCurrentProfile): CurrentProfileResult[
    PreparedCurrentChainUpdate] =
  ## Return the exact retained authenticated producer without accepting a replacement map or child.
  if not captured.initialized:
    return CurrentProfileResult[PreparedCurrentChainUpdate](
        status: CurrentProfileError.Uninitialized)
  CurrentProfileResult[PreparedCurrentChainUpdate](status: CurrentProfileError.None,
      completed: captured.source)
