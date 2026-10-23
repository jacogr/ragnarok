# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded selected-chain parent profile retains the original full view, parameters and exact physical head without inventing an execution certificate.
import ../chain/[genesis, provider, parameters]
import ../codec/[bounded, assurances, state_composition, state_layout, state_safrole, state_consensus]
import ./store
type
  ParentProfileLimits* = object ## Rolling/finalized owners, view/index bytes and previous-roster decode resources have independent admission.
    blocks*, validators*: ElementLimit
    viewBytes*, previousBytes*: ByteLimit
  ParentProfileInfo* = object ## Fixed copied extent observations grant neither finality nor installation authority.
    view*: ChainViewRetentionInfo
    previousBytes*: uint64
  ParentProfileData = ref object # One acyclic original view plus fixed head/profile facts; no detached source substitution.
    view: ChainView
    context: BlockSnapshotContext
    profile: StateProfile
    info: ParentProfileInfo
  SelectedParentProfile* = object ## Configured selected parent is distinct from a completed current transition.
    data: nil ParentProfileData
  ParentProfileError* {.pure.} = enum ## Missing head/previous chapter, malformed roster, resource refusal and defaults remain distinct.
    Uninitialized, None, MissingHead, LimitExceeded, MissingPrevious, PreviousFailure,
      TrailingPrevious, InvalidProfile
  ParentProfileResult*[T] = object ## Private selected payload and genuinely failed codec reason have guarded extraction.
    case status: ParentProfileError
    of None:
      completed: T
    of PreviousFailure:
      previousReason: StateComponentError
    else:
      discard # No failed/default alternative carries a selected parent prefix.
func error*[T](outcome: ParentProfileResult[T]): ParentProfileError =
  ## Observe the immutable selected stage only.
  outcome.status
func value*[T](outcome: ParentProfileResult[T]): T {.inline, requires: outcome.status ==
    ParentProfileError.None.} =
  ## Extract only a complete initialized parent owner, fixed fact or admitted view copy.
  outcome.completed
func previousError*[T](outcome: ParentProfileResult[T]): StateComponentError {.inline,
    requires: outcome.status == ParentProfileError.PreviousFailure.} =
  ## Preserve the original previous-roster decoder failure without a default successful roster.
  outcome.previousReason
proc captureParentProfile*(view: ChainView, limits: ParentProfileLimits): ParentProfileResult[
    SelectedParentProfile] =
  ## Inspect original fixed observations and admit all view/index retention before any whole-view or C9 payload copy.
  if view.retainedCount == 0:
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.MissingHead)
  let retention = view.viewRetentionInfo
  if uint64(retention.owners) > uint64(limits.blocks) or retention.bytes > min(uint64(
      limits.viewBytes), uint64(high(int))):
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.LimitExceeded)
  let context = view.bestBlockContext
  let previous = context.state.lookup(chapterKey(StateChapter(9)))
  if previous.error == StateStoreError.MissingKey:
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.MissingPrevious)
  if previous.error != StateStoreError.None:
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.InvalidProfile)
  let extent = uint64(previous.value.byteLength)
  if extent > uint64(limits.previousBytes):
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.LimitExceeded)
  let input = previous.value.bytes
  let cores = CoreCount(context.parameters.get(coreCount))
  let decoded = decodeStateValidators(input, ValidatorStateConfig(cores: cores,
      validators: limits.validators, maxBytes: limits.previousBytes))
  if decoded.error != StateComponentError.None:
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.PreviousFailure,
        previousReason: decoded.error)
  if decoded.value.consumed != input.len:
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.TrailingPrevious)
  let count = decoded.value.value.validatorCount
  if count.error != StateComponentError.None:
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.PreviousFailure,
        previousReason: count.error)
  if count.value < 0:
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.InvalidProfile)
  let profile = StateProfile(cores: cores, current: context.validators, previous: ValidatorCount(
      uint64(count.value)), epochSlots: EpochSlots(context.parameters.get(epochPeriod)))
  if not profile.valid:
    return ParentProfileResult[SelectedParentProfile](status: ParentProfileError.InvalidProfile)
  ParentProfileResult[SelectedParentProfile](status: ParentProfileError.None,
      completed: SelectedParentProfile(data: ParentProfileData(view: view, context: context,
      profile: profile, info: ParentProfileInfo(view: retention, previousBytes: extent))))
proc parentProfileInfo*(source: SelectedParentProfile): ParentProfileResult[ParentProfileInfo] =
  ## Copy bounded retention/decode observations only from an initialized selected parent.
  let data = source.data
  if data == nil:
    return ParentProfileResult[ParentProfileInfo](status: ParentProfileError.Uninitialized)
  ParentProfileResult[ParentProfileInfo](status: ParentProfileError.None, completed: data.info)
proc parentStateProfile*(source: SelectedParentProfile): ParentProfileResult[StateProfile] =
  ## Copy cardinalities derived from the same exact head and previous chapter.
  let data = source.data
  if data == nil:
    return ParentProfileResult[StateProfile](status: ParentProfileError.Uninitialized)
  ParentProfileResult[StateProfile](status: ParentProfileError.None, completed: data.profile)
proc parentContext*(source: SelectedParentProfile): ParentProfileResult[BlockSnapshotContext] =
  ## Retain original fixed head/header/map/full-Parameters facts without copying its private indexes.
  let data = source.data
  if data == nil:
    return ParentProfileResult[BlockSnapshotContext](status: ParentProfileError.Uninitialized)
  ParentProfileResult[BlockSnapshotContext](status: ParentProfileError.None,
      completed: data.context)
proc copyParentView*(source: SelectedParentProfile, limit: ByteLimit): ParentProfileResult[ChainView] =
  ## Explicitly admit a complete detached view/index copy, preserving ordered history and presence/absence of finality.
  let data = source.data
  if data == nil:
    return ParentProfileResult[ChainView](status: ParentProfileError.Uninitialized)
  if data.info.view.bytes > uint64(limit):
    return ParentProfileResult[ChainView](status: ParentProfileError.LimitExceeded)
  ParentProfileResult[ChainView](status: ParentProfileError.None, completed: data.view)
