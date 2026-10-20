# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Check original computed core/shards against the exact authenticated posterior active population.

import ../chain/parameters
import ../codec/[assurances, bounded, state_safrole, state_layout, work_report]
import ./[computed_transition, computed_profile, computed_lookup, computed_recent, computed_state,
  computed_links, computed_guarantee, computed_report, block_transition, store]

type
  ComputedRosterError* {.pure.} = enum ## Refusals carry neither a roster certificate nor partial decoded state.
    Uninitialized, None, InvalidSource, MissingState, InvalidState, LimitExceeded,
    InactiveCore, WrongErasureShards
  ComputedRosterLimits* = object ## Independent local record/whole-chapter ceilings never replace configured protocol bounds.
    validators*: ElementLimit
    bytes*: ByteLimit
  ComputedRosterInfo* = object ## Fixed copied population facts grant no source or posterior replacement authority.
    population*: ValidatorCount
    activeCores*: CoreCount
  ComputedRosterData = ref object ## Immutable acyclic provenance retains original authenticated computation and decoded posterior records.
    source: TransitionBoundComputedReport
    active: ValidatorStateSnapshot
  RosterEligibleComputedReport* = object ## Current population eligibility precedes assignment, evaluation-slot and signing checks.
    data: nil ComputedRosterData
  ComputedRosterResult*[T] = object ## Private selected success alone carries extractable application data.
    case status: ComputedRosterError
    of None:
      completed: T
    else:
      discard # Defaults/refusals expose reasons alone.

func error*[T](outcome: ComputedRosterResult[T]): ComputedRosterError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedRosterResult[T]): T
    {.requires: outcome.status == ComputedRosterError.None.} =
  ## Preserve selected-success extraction in optimized execution.
  outcome.completed
proc computedRosterSource*(bound: RosterEligibleComputedReport): ComputedRosterResult[
    TransitionBoundComputedReport] =
  ## Share the exact original authenticated transition and configured computed source.
  let data = bound.data
  if data == nil: return ComputedRosterResult[TransitionBoundComputedReport](
      status: ComputedRosterError.Uninitialized)
  ComputedRosterResult[TransitionBoundComputedReport](status: ComputedRosterError.None,
      completed: data.source)
proc computedRosterActive*(bound: RosterEligibleComputedReport): ComputedRosterResult[
    ValidatorStateSnapshot] =
  ## Share immutable posterior validator storage; ordinal queries return independent fixed record copies.
  let data = bound.data
  if data == nil: return ComputedRosterResult[ValidatorStateSnapshot](
      status: ComputedRosterError.Uninitialized)
  ComputedRosterResult[ValidatorStateSnapshot](status: ComputedRosterError.None,
      completed: data.active)
proc computedRosterInfo*(bound: RosterEligibleComputedReport): ComputedRosterResult[
    ComputedRosterInfo] =
  ## Derive copied population facts from the retained exact posterior roster.
  let data = bound.data
  if data == nil: return ComputedRosterResult[ComputedRosterInfo](
      status: ComputedRosterError.Uninitialized)
  let count = uint64(validatorCount(data.active).value)
  ComputedRosterResult[ComputedRosterInfo](status: ComputedRosterError.None,
    completed: ComputedRosterInfo(population: ValidatorCount(count), activeCores: CoreCount(count div 3)))
proc checkComputedRoster*(source: TransitionBoundComputedReport,
    limits: ComputedRosterLimits): ComputedRosterResult[RosterEligibleComputedReport] =
  ## Decode only authenticated posterior C8, then check original core activity and exact shard population without hashing or writes.
  template fail(reason: ComputedRosterError) =
    return ComputedRosterResult[RosterEligibleComputedReport](status: reason)
  let retained = source.computedTransitionStage
  if retained.error != ComputedTransitionError.None: fail(ComputedRosterError.InvalidSource)
  let snapshot = retained.value.value.snapshot
  let read = snapshot.lookup(chapterKey(StateChapter(8)))
  if read.error != StateStoreError.None: fail(ComputedRosterError.MissingState)
  if uint64(read.value.byteLength) > uint64(limits.bytes): fail(ComputedRosterError.LimitExceeded)
  let configured = source.computedTransitionSource.value
  let parameters = configured.computedProfileContext.value.parameters
  let raw = read.value.bytes
  let decoded = decodeStateValidators(raw, ValidatorStateConfig(cores: CoreCount(parameters.get(
      coreCount)),
    validators: limits.validators, maxBytes: limits.bytes))
  if decoded.error == StateComponentError.LimitExceeded: fail(ComputedRosterError.LimitExceeded)
  if decoded.error != StateComponentError.None: fail(ComputedRosterError.InvalidState)
  if decoded.value.consumed != raw.len: fail(ComputedRosterError.InvalidState) # State chapters cannot hide a suffix behind prefix decoding.
  let active = decoded.value.value
  let population = uint64(validatorCount(active).value)
  let state = configured.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value
  let report = state.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value.computedReportInfo.value
  if uint64(report.core) >= population div 3: fail(ComputedRosterError.InactiveCore)
  if uint64(report.header.erasureShards) != population: fail(ComputedRosterError.WrongErasureShards)
  ComputedRosterResult[RosterEligibleComputedReport](status: ComputedRosterError.None,
    completed: RosterEligibleComputedReport(data: ComputedRosterData(source: source,
        active: active)))
