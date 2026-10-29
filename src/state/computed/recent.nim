# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Derive corrected recent history from the original admitted state and match one complete computed-report anchor tuple.

import ../../codec/[bounded, header]
import ../../codec/state/[history as state_history, layout as state_layout, trie as state_trie]
import ../../chain/parameters
import ./[state as computed_state, links as computed_links, guarantee as computed_guarantee,
    report as computed_report]
import "../block/admission" as block_admission
import ../[store, history]
import ../availability/specifier as availability_specifier
import "../export/erasure" as export_erasure
import ../bundle_erasure
import ../erasure/layout as erasure_layout
import ../[auditable_bundle, input_refinement]
import ../report/identity as report_identity
import ../authorized_refinement
import ../authorization/invocation as authorization_invocation

type
  ComputedRecentError* {.pure.} = enum ## Refusals contain no corrected prefix or partially matched anchor certificate.
    Uninitialized, None, InvalidSource, InvalidConfig, MissingState, InvalidHistory,
    LimitExceeded, InvalidRecentAnchor
  ComputedRecentData = ref object ## Immutable acyclic ownership retains exact source, corrected history and one copied matching record.
    source: StateBoundComputedReport
    history: HistorySnapshot
    anchor: HistoryBlockInfo
  RecentComputedReport* = object ## Recent tuple correspondence alone does not certify lookup ancestry or signing eligibility.
    data: nil ComputedRecentData
  ComputedRecentResult*[T] = object ## Private successful selection guards every application payload.
    case status: ComputedRecentError
    of None:
      completed: T
    else:
      discard                       # Defaults and refusals expose reasons alone.

func error*[T](outcome: ComputedRecentResult[T]): ComputedRecentError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedRecentResult[T]): T
    {.requires: outcome.status == ComputedRecentError.None.} =
  ## Preserve checked success extraction in optimized execution.
  outcome.completed
proc computedRecentSource*(recent: RecentComputedReport): ComputedRecentResult[
    StateBoundComputedReport] =
  ## Retain exact original computation and admitted state instead of a substitute report/header.
  let data = recent.data
  if data == nil: return ComputedRecentResult[StateBoundComputedReport](
      status: ComputedRecentError.Uninitialized)
  ComputedRecentResult[StateBoundComputedReport](status: ComputedRecentError.None,
      completed: data.source)
proc computedRecentHistory*(recent: RecentComputedReport): ComputedRecentResult[HistorySnapshot] =
  ## Share only the complete corrected immutable history, leaving original committed C3 untouched.
  let data = recent.data
  if data == nil: return ComputedRecentResult[HistorySnapshot](
      status: ComputedRecentError.Uninitialized)
  ComputedRecentResult[HistorySnapshot](status: ComputedRecentError.None, completed: data.history)
proc computedRecentAnchor*(recent: RecentComputedReport): ComputedRecentResult[HistoryBlockInfo] =
  ## Copy the single matched record; fields from different records cannot be spliced into authority.
  let data = recent.data
  if data == nil: return ComputedRecentResult[HistoryBlockInfo](
      status: ComputedRecentError.Uninitialized)
  ComputedRecentResult[HistoryBlockInfo](status: ComputedRecentError.None, completed: data.anchor)
proc checkComputedRecentAnchor*(source: StateBoundComputedReport,
    config: HistoryConfig): ComputedRecentResult[RecentComputedReport] =
  ## Preflight original state/profile, correct only its latest root, then match all four claimed fields together.
  template fail(reason: ComputedRecentError) =
    return ComputedRecentResult[RecentComputedReport](status: reason)
  let selected = source.computedStateSnapshot
  if selected.error != ComputedStateError.None: fail(ComputedRecentError.InvalidSource)
  let state = selected.value
  let report = source.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value
  let identity = report.computedReportSource.value.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  let cores = identity.identitySource.value.authorizedSource.value.authorizationParameters.value.get(coreCount)
  if uint64(config.cores) < 2 or uint64(config.cores) > 341 or uint64(config.cores) != cores:
    fail(ComputedRecentError.InvalidConfig) # No permissive caller profile can replace original execution domains.
  let chapter = state.lookup(chapterKey(StateChapter(3)))
  if chapter.error == StateStoreError.MissingKey: fail(ComputedRecentError.MissingState)
  if chapter.error != StateStoreError.None: fail(ComputedRecentError.InvalidHistory)
  if uint64(chapter.value.byteLength) > uint64(config.maxBytes): fail(
      ComputedRecentError.LimitExceeded) # Before copying any chapter bytes.
  let wire = chapter.value.bytes
  let decoded = decodeHistoryState(wire, config)
  if decoded.error == HistoryError.LimitExceeded: fail(ComputedRecentError.LimitExceeded)
  if decoded.error != HistoryError.None: fail(ComputedRecentError.InvalidHistory)
  if decoded.value.consumed != wire.len: fail(ComputedRecentError.InvalidHistory) # Exact original C3, never a valid prefix with suffix.
  let count = historyInfo(decoded.value.snapshot).value.blocks
  if count > 0:
    # Only a record naming this exact admitted parent can receive the parent's posterior-root correction.
    let latest = historyBlockAt(decoded.value.snapshot, HistoryBlockIndex(uint64(count-1))).value
    let binding = source.computedStateAdmission.value
    let child = headerInfo(binding.admittedHeader).value.unsigned
    let parent = headerInfo(binding.admittedParent).value.unsigned
    if array[32, byte](latest.header) != array[32, byte](child.parent) or uint32(latest.slot) !=
        uint32(parent.slot):
      fail(ComputedRecentError.InvalidHistory)
  let corrected = correctHistoryParent(decoded.value.snapshot,
    HistoryStateRoot(array[32, byte](state.commitment.root)), config)
  if corrected.error == HistoryTransitionError.LimitExceeded: fail(
      ComputedRecentError.LimitExceeded)
  if corrected.error != HistoryTransitionError.None: fail(ComputedRecentError.InvalidHistory)
  let canonical = decodeHistoryState(corrected.value.value, config)
  if canonical.error == HistoryError.LimitExceeded: fail(ComputedRecentError.LimitExceeded)
  if canonical.error != HistoryError.None: fail(ComputedRecentError.InvalidHistory)
  if canonical.value.consumed != corrected.value.value.len: fail(ComputedRecentError.InvalidHistory)
  let header = report.computedReportInfo.value.header
  # Every equality must hold for the same corrected record; there is no independent per-field membership fallback.
  for index in 0..<count:
    let record = historyBlockAt(canonical.value.snapshot, HistoryBlockIndex(uint64(index))).value
    let sameHash = header.anchor.bytes == array[32, byte](record.header)
    let sameState = header.stateRoot.bytes == array[32, byte](record.state)
    let samePeak = header.accumulationRoot.bytes == array[32, byte](record.superPeak)
    let sameSlot = uint32(header.anchorSlot) == uint32(record.slot)
    if sameHash and sameState and samePeak and sameSlot:
      return ComputedRecentResult[RecentComputedReport](status: ComputedRecentError.None,
        completed: RecentComputedReport(data: ComputedRecentData(source: source,
          history: canonical.value.snapshot, anchor: record)))
  fail(ComputedRecentError.InvalidRecentAnchor)
