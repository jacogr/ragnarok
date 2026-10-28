# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reporting_assurance.tex contextual validity: package uniqueness, dependencies and
## segment mappings.
##
## Exposes inspectReportPackages/checkReportPackages and access to the certified recent-report
## context.

import std/algorithm
import ../codec/bounded as codec_bounded
import ../codec/state_history as codec_state_history
import ../codec/state_availability as codec_state_availability
import ../codec/state_workqueues as codec_state_workqueues
import ../codec/report_owned as codec_report_owned
import ../codec/work_report as codec_work_report
import ./report_anchors as state_report_anchors
import ./report_policy as state_report_policy
import ./guarantee_credentials as state_guarantee_credentials
import ./store as state_store
import ../codec/state_layout as codec_state_layout

type
  ReportPackageConfig* = object ## State decode bounds and per-index item ceilings bound parent copies, sorting scratch and lookups.
    availability*: AvailabilityConfig
    queues*: WorkQueueConfig
    indexItems*: ElementLimit
  ReportPackageError* {.pure.} = enum ## Default and failed alternatives contain no certificate, partial index or accepted prefix.
    Uninitialized, None, InvalidRecent, InvalidCredentials, InvalidHistory, InvalidConfig,
    MissingState, InvalidState, LimitExceeded, DuplicatePackage, MissingDependency, InvalidSegmentRoot
  ## Acyclic private owner retains the exact earlier stage and all decoded parent pipeline views.
  PackageData = ref object
    recent: RecentAnchoredReports
    availability: AvailabilitySnapshot
    ready: ReadySnapshot
    accumulated: AccumulatedSnapshot
  PackageCheckedReports* = object ## Package checks do not certify lookup ancestry, core capacity or C(10) publication.
    data: nil PackageData
  ReportPackageResult*[T] = object ## Only complete application success carries an immutable owner.
    case status: ReportPackageError
    of None:
      completed: T
    else:
      discard                      # Failed/default results cannot expose successful data.

func error*[T](outcome: ReportPackageResult[T]): ReportPackageError =
  ## Read a failure reason without allowing external retagging.
  outcome.status
func value*[T](outcome: ReportPackageResult[T]): T {.inline,
    requires: outcome.status == ReportPackageError.None.} =
  ## Extract only a completely selected success under the checked-build contract.
  outcome.completed

proc packageRecent*(owner: PackageCheckedReports): ReportPackageResult[RecentAnchoredReports] =
  ## Retain the exact recent/policy context for later lookup/capacity admission stages.
  let data = owner.data
  if data == nil:
    return ReportPackageResult[RecentAnchoredReports](
        status: ReportPackageError.Uninitialized) # No fabricated empty batch.
  ReportPackageResult[RecentAnchoredReports](status: ReportPackageError.None,
      completed: data.recent)

## Compare fixed package octets without silently interchanging root/hash domains.
func compareHash(a, b: PackageHash): int =
  # The first unequal octet decides lexicographic identity order.
  for i in 0..<32:
    if a.bytes[i] < b.bytes[i]: return -1 # Smaller key precedes larger.
    if a.bytes[i] > b.bytes[i]: return 1 # Larger key follows smaller.
  0

## Sort complete pairs, retaining distinct roots for the same historical key as set-union members.
func comparePair(a, b: ReportedPackage): int =
  let key = compareHash(a.package, b.package)
  if key != 0: return key # Root bytes only order equal keys.
  # Exact pair membership implements the paper's union of key/value pairs.
  for i in 0..<32:
    if a.segment.bytes[i] < b.segment.bytes[i]: return -1 # Earlier root octet.
    if a.segment.bytes[i] > b.segment.bytes[i]: return 1 # Later root octet.
  0

## Binary search privately sorted identities; repeated existing identities are ordinary set-union evidence.
func contains(values: seq[PackageHash], key: PackageHash): bool =
  var low = 0
  var high = values.len
  # Halving bounds avoids repeated scans over large accumulated/ready rings.
  while low < high:
    let middle = low+(high-low) div 2
    if compareHash(values[middle], key) < 0:
      low = middle+1 # Key lies strictly after the midpoint.
    else:
      high = middle # Keep the first candidate equal to or greater than the key.
  low < values.len and compareHash(values[low], key) == 0

## Search exact key/root pairs; a matching key with a different root cannot satisfy this check.
func contains(values: seq[ReportedPackage], key: ReportedPackage): bool =
  var low = 0
  var high = values.len
  # Search sorted copied pairs without exporting mutable index storage.
  while low < high:
    let middle = low+(high-low) div 2
    if comparePair(values[middle], key) < 0:
      low = middle+1 # Pair follows this candidate.
    else:
      high = middle # Preserve the first possible exact match.
  low < values.len and comparePair(values[low], key) == 0

proc inspectReportPackages*(credentials: VerifiedGuaranteeCredentials, history: HistorySnapshot,
    known: openArray[PackageHash], limit: ElementLimit): ReportPackageError =
  ## Reason-only relation inspection; known is caller-supplied existing-pipeline evidence, not a state certificate.
  ## Inputs are borrowed stably for this call. This helper never produces an application admission owner.
  ## The state-backed entry point below derives known itself; projections may use the STF's summarized known set.
  let records = credentials.verifiedGuaranteeCount
  if records.error != GuaranteeCredentialError.None:
    return ReportPackageError.InvalidCredentials # No raw/default extrinsic bypass.
  let info = historyInfo(history)
  if info.error != HistoryError.None:
    return ReportPackageError.InvalidHistory # Missing history cannot mean an empty set.
  let maximum = uint64(limit)
  if uint64(records.value) > maximum or uint64(known.len) > maximum or
      maximum > uint64(high(int) div sizeof(ReportedPackage)):
    return ReportPackageError.LimitExceeded # Bound descriptor storage before any index allocation.
  var count = 0'u64
  # Count historical pairs before copying, with checked aggregate growth.
  for i in 0..<info.value.blocks:
    let record = historyBlockAt(history, HistoryBlockIndex(i)).value
    if uint64(record.packages) > maximum-count:
      return ReportPackageError.LimitExceeded # No overflow when accumulating package counts.
    count += uint64(record.packages)
  if uint64(records.value) > maximum-count or uint64(known.len) > maximum-count:
    return ReportPackageError.LimitExceeded # Both mapping and existing-key indices have independent same-sized ceilings.
  var incoming = newSeq[PackageHash](records.value)
  var existing = newSeq[PackageHash](known.len+int(count))
  var available = newSeq[PackageHash](records.value+int(count))
  var mappings = newSeq[ReportedPackage](records.value+int(count))
  # Preserve caller evidence in a private sorting index, never normalizing protocol fields.
  for i in 0..<known.len: existing[i] = known[i]
  var cursor = 0
  # Every recent pair contributes to duplicate exclusion and dependency/root availability.
  for i in 0..<info.value.blocks:
    let record = historyBlockAt(history, HistoryBlockIndex(i)).value
    for j in 0..<record.packages:
      let pair = historyPackageAt(history, HistoryBlockIndex(i), HistoryPackageIndex(j)).value
      existing[known.len+cursor] = pair.package
      available[cursor] = pair.package
      mappings[cursor] = pair
      inc cursor # Preflight proved all destination extents.
  # Collect the whole batch first: forward references, self references and dependency cycles are allowed.
  for i in 0..<records.value:
    let report = ownedReportInfo(credentials.verifiedGuaranteeAt(i).value.report).value
    incoming[i] = report.header.packageHash
    available[cursor+i] = report.header.packageHash
    mappings[cursor+i] = ReportedPackage(package: report.header.packageHash,
        segment: report.header.segmentRoot)
  incoming.sort(compareHash)
  existing.sort(compareHash)
  available.sort(compareHash)
  mappings.sort(comparePair)
  # Any repeated incoming identity or prior-pipeline occurrence rejects the entire batch.
  for i in 0..<incoming.len:
    if (i > 0 and compareHash(incoming[i-1], incoming[i]) == 0) or existing.contains(incoming[i]):
      return ReportPackageError.DuplicatePackage # Segment differences cannot create a new package identity.
  # Resolve prerequisites and lookup keys only against current reports or recent history, never queues/accumulated alone.
  for i in 0..<records.value:
    let report = credentials.verifiedGuaranteeAt(i).value.report
    let meta = ownedReportInfo(report).value
    for j in 0..<meta.prerequisiteCount:
      if not available.contains(ownedReportPrerequisite(report, j).value):
        return ReportPackageError.MissingDependency # No pipeline-only dependency fallback.
    for j in 0..<meta.lookupCount:
      let pair = ownedReportLookup(report, j).value
      # Exact pair membership also establishes lookup-key eligibility; missing and wrong pairs share the STF root refusal.
      if not mappings.contains(ReportedPackage(package: pair.packageHash,
          segment: pair.segmentRoot)):
        return ReportPackageError.InvalidSegmentRoot # Verify the associated root, not just the key.
  ReportPackageError.None

proc checkReportPackages*(recent: RecentAnchoredReports,
    config: ReportPackageConfig): ReportPackageResult[PackageCheckedReports] =
  ## Load exact parent C(10)/C(14)/C(15), derive the prior-pipeline identities and certify all package relations.
  ## Corrected recent history retains the parent's package dictionaries; no post-assurance substitution or writes occur.
  let policy = recent.recentPolicy
  if policy.error != ReportAnchorError.None:
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.InvalidRecent) # Require completed policy/recent context.
  if uint64(config.queues.cores) < 2 or uint64(config.queues.cores) > 341 or
      uint64(config.queues.cores) != uint64(config.availability.guarantee.cores):
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.InvalidConfig) # One explicit chain profile across parent chapters.
  let parent = policy.value.policyParent.value
  let assignments = parent.lookup(chapterKey(StateChapter(10)))
  let ready = parent.lookup(chapterKey(StateChapter(14)))
  let accumulated = parent.lookup(chapterKey(StateChapter(15)))
  if assignments.error == StateStoreError.MissingKey or ready.error == StateStoreError.MissingKey or
      accumulated.error == StateStoreError.MissingKey:
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.MissingState) # Absence never means an empty ring/core table.
  if assignments.error != StateStoreError.None or ready.error != StateStoreError.None or
      accumulated.error != StateStoreError.None:
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.InvalidState) # Refuse unusable parent views.
  if uint64(assignments.value.byteLength) > uint64(config.availability.maxBytes) or
      uint64(ready.value.byteLength) > uint64(config.queues.maxBytes) or
      uint64(accumulated.value.byteLength) > uint64(config.queues.maxBytes):
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.LimitExceeded) # Check before copying any chapter bytes.
  let assignmentRead = decodeAvailabilityState(assignments.value.bytes, config.availability)
  let readyRead = decodeReadyState(ready.value.bytes, config.queues)
  let accumulatedRead = decodeAccumulatedState(accumulated.value.bytes, config.queues)
  let limitedAssignments = assignmentRead.error == AvailabilityError.LimitExceeded
  let limitedReady = readyRead.error == WorkQueueError.LimitExceeded
  let limitedAccumulated = accumulatedRead.error == WorkQueueError.LimitExceeded
  if limitedAssignments or limitedReady or limitedAccumulated:
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.LimitExceeded) # Preserve child resource refusals.
  let validAssignments = assignmentRead.error == AvailabilityError.None
  let validReady = readyRead.error == WorkQueueError.None
  let validAccumulated = accumulatedRead.error == WorkQueueError.None
  if not validAssignments or not validReady or not validAccumulated:
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.InvalidState) # Never extract a failed child payload.
  let exactAssignments = assignmentRead.value.consumed == assignments.value.byteLength
  let exactReady = readyRead.value.consumed == ready.value.byteLength
  let exactAccumulated = accumulatedRead.value.consumed == accumulated.value.byteLength
  if not exactAssignments or not exactReady or not exactAccumulated:
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.InvalidState) # Exact values, no prefix acceptance.
  let assignmentMeta = availabilityInfo(assignmentRead.value.snapshot).value
  let readyMeta = readyInfo(readyRead.value.snapshot).value
  let accumulatedMeta = accumulatedInfo(accumulatedRead.value.snapshot).value
  let maximum = uint64(config.indexItems)
  if maximum > uint64(high(int) div sizeof(ReportedPackage)):
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.LimitExceeded) # Bound every index descriptor before allocation.
  if uint64(assignmentMeta.present) > maximum:
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.LimitExceeded) # The first source must fit before subtraction.
  if uint64(readyMeta.items) > maximum-uint64(assignmentMeta.present):
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.LimitExceeded) # Prove the first sum before adding it.
  let first = uint64(assignmentMeta.present)+uint64(readyMeta.items)
  if uint64(accumulatedMeta.items) > maximum-first:
    return ReportPackageResult[PackageCheckedReports](
        status: ReportPackageError.LimitExceeded) # Check the last aggregate before native narrowing.
  var known = newSeq[PackageHash](int(first+uint64(accumulatedMeta.items)))
  var cursor = 0
  # Use prior assignments even if assurances/timeouts would free these cores later in this block.
  for i in 0..<assignmentMeta.cores:
    let entry = availabilityAt(assignmentRead.value.snapshot, AssignmentCoreIndex(i)).value
    if entry.present:
      known[cursor] = ownedReportInfo(entry.guarantee.report).value.header.packageHash
      inc cursor # Only present reports contribute identities.
  # Ready dependencies are not report identities; inspect only each ready report's own package hash.
  for i in 0..<readyMeta.slots:
    let slot = WorkQueueSlot(i)
    for j in 0..<readySlotCount(readyRead.value.snapshot, slot).value:
      known[cursor] = ownedReportInfo(readyItemAt(readyRead.value.snapshot, slot, ReadyItemIndex(
          j)).value.report).value.header.packageHash
      inc cursor # Preserve all reports across the fixed epoch ring.
  # Every accumulated slot contributes its mathematical package set, independent of row placement.
  for i in 0..<accumulatedMeta.slots:
    let slot = WorkQueueSlot(i)
    for j in 0..<accumulatedSlotCount(accumulatedRead.value.snapshot, slot).value:
      known[cursor] = accumulatedHashAt(accumulatedRead.value.snapshot, slot, WorkQueueHashIndex(j)).value
      inc cursor # Aggregate preflight proved the destination extent.
  let reason = inspectReportPackages(policy.value.policyCredentials.value,
    recent.anchorHistory.value,
    known, config.indexItems)
  if reason != ReportPackageError.None:
    return ReportPackageResult[PackageCheckedReports](
        status: reason) # No state-backed certificate from partial relation success.
  ReportPackageResult[PackageCheckedReports](status: ReportPackageError.None,
    completed: PackageCheckedReports(data: PackageData(recent: recent,
      availability: assignmentRead.value.snapshot,
      ready: readyRead.value.snapshot, accumulated: accumulatedRead.value.snapshot)))
