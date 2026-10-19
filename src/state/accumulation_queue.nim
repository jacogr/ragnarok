# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accumulation.tex, History and Queuing: D, E and wave-ordered Q only.
## Plans neither execute reports nor publish execution-dependent C(14)/C(15).
##
## Exposes bounded AccumulationQueueConfig, immutable projection/block-bound plan handles,
## planAccumulationQueues/planBlockAccumulationQueue and checked report/dependency/source access.

import std/algorithm
import ../codec/[bounded, state_workqueues, report_owned, owned, work_report, header,
  state_layout]
import ./[report_admission, block_transition, block_admission, availability, store]

type
  AccumulationQueueConfig* = object ## Independent aggregate bounds cover parent plus incoming descriptors before scratch allocation.
    queues*: WorkQueueConfig
    items*, dependencies*: ElementLimit
  AccumulationIndex* = distinct uint64 ## Nominal priority/queue ordinal cannot be confused with a ring slot or package hash index.
  AccumulationQueueError* {.pure.} = enum ## Default/refused outcomes contain no partial priority sequence or mutable queue.
    Uninitialized, None, InvalidConfig, InvalidState, InvalidReport, InvalidAdmission,
    MissingState, LimitExceeded, InvalidIndex
  ## Private acyclic storage retains decoded parent owners and the original complete report handles.
  QueueData = ref object
    ready: ReadySnapshot
    accumulated: AccumulatedSnapshot
    queue: ReadyRow
    priority: seq[OwnedReport]
    immediate: int
  AccumulationQueuePlan* = object ## A pure projection plan is deliberately not an admitted-block or execution certificate.
    data: nil QueueData
  ## Private binding retains the genuine completed report-admission owner and its derived projection.
  BlockQueueData = ref object
    reports: AdmittedReports
    plan: AccumulationQueuePlan
  BlockAccumulationQueue* = object ## Only the state-backed entry point can create this block-bound handle.
    data: nil BlockQueueData
  AccumulationQueueResult*[T] = object ## Only selected complete success exposes a value under checked-build contracts.
    # Select payload storage only for a completed plan/member.
    case status: AccumulationQueueError
    of None:
      completed: T # Success alone retains the requested typed value.
    else:
      discard      # No partial progress or fabricated empty success.

func error*[T](outcome: AccumulationQueueResult[T]): AccumulationQueueError =
  ## Inspect a reason without exposing writable variant state.
  outcome.status
func value*[T](outcome: AccumulationQueueResult[T]): T {.inline,
    requires: outcome.status == AccumulationQueueError.None.} =
  ## Extract only a successful immutable handle or copied member.
  outcome.completed

## Fixed octets order identities without exchanging their nominal hash domain.
func compareHash(a, b: PackageHash): int =
  # Compare fixed identity bytes from most significant octet to least.
  for i in 0..<32:
    if a.bytes[i] < b.bytes[i]: return -1 # First smaller byte decides.
    if a.bytes[i] > b.bytes[i]: return 1 # First larger byte decides.
  0

## Binary membership in a sorted scratch set; duplicates in the index are harmless union evidence.
func contains(values: seq[PackageHash], key: PackageHash): bool =
  var low = 0
  var high = values.len
  # Halve the remaining ordered candidates without overflowing midpoint arithmetic.
  while low < high:
    let middle = low+(high-low) div 2
    if compareHash(values[middle], key) < 0:
      low = middle+1 # Skip strictly smaller candidates.
    else:
      high = middle # Preserve the first possible equal identity.
  low < values.len and compareHash(values[low], key) == 0

## E preserves sequence order, drops satisfied packages and subtracts their hashes from dependencies.
## Inputs and output are private bounded scratch; report owners stay shared and immutable.
proc edit(rows: ReadyRow, hashes: seq[PackageHash]): ReadyRow =
  result = @[]
  # Apply E to each original position so retained reports preserve their priority.
  for row in rows:
    if hashes.contains(ownedReportInfo(row.report).value.header.packageHash):
      continue # The whole report has already been selected/accumulated.
    var retained = ReadyItem(report: row.report, dependencies: @[])
    # Remove only dependencies satisfied by the supplied hash set.
    for dependency in row.dependencies:
      if not hashes.contains(dependency):
        retained.dependencies.add(dependency) # Only still-unfulfilled identities survive E.
    result.add(retained)

proc accumulationCount*(plan: AccumulationQueuePlan): AccumulationQueueResult[int] =
  ## Count copied priority reports; default owners are not valid empty plans.
  let data = plan.data
  # A default handle owns no validated storage, even for an empty-looking extraction.
  if data == nil: return AccumulationQueueResult[int](status: AccumulationQueueError.Uninitialized)
  AccumulationQueueResult[int](status: AccumulationQueueError.None, completed: data.priority.len)

proc accumulationImmediateCount*(plan: AccumulationQueuePlan): AccumulationQueueResult[int] =
  ## Return the immediate prefix length, before dependency-wave selection.
  let data = plan.data
  # A default handle owns no validated storage, even for an empty-looking extraction.
  if data == nil: return AccumulationQueueResult[int](status: AccumulationQueueError.Uninitialized)
  AccumulationQueueResult[int](status: AccumulationQueueError.None, completed: data.immediate)

proc accumulationAt*(plan: AccumulationQueuePlan, index: AccumulationIndex): AccumulationQueueResult[OwnedReport] =
  ## Retain an exact complete report after plan/caller storage leaves scope.
  let data = plan.data
  # A default handle owns no validated storage, even for an empty-looking extraction.
  if data == nil: return AccumulationQueueResult[OwnedReport](
      status: AccumulationQueueError.Uninitialized)
  if uint64(index) >= uint64(data.priority.len):
    return AccumulationQueueResult[OwnedReport](status: AccumulationQueueError.InvalidIndex) # Before narrowing/access.
  AccumulationQueueResult[OwnedReport](status: AccumulationQueueError.None,
    completed: data.priority[int(uint64(index))])

proc accumulationQueuedCount*(plan: AccumulationQueuePlan): AccumulationQueueResult[int] =
  ## Count q before Q; this is planning evidence, never the execution-dependent posterior ready ring.
  let data = plan.data
  # A default handle owns no validated storage, even for an empty-looking extraction.
  if data == nil: return AccumulationQueueResult[int](status: AccumulationQueueError.Uninitialized)
  AccumulationQueueResult[int](status: AccumulationQueueError.None, completed: data.queue.len)

proc accumulationQueuedAt*(plan: AccumulationQueuePlan,
    index: AccumulationIndex): AccumulationQueueResult[ReadyItemInfo] =
  ## Inspect q's retained report and dependency count without exporting its mutable set storage.
  let data = plan.data
  # A default handle owns no validated storage, even for an empty-looking extraction.
  if data == nil: return AccumulationQueueResult[ReadyItemInfo](
      status: AccumulationQueueError.Uninitialized)
  if uint64(index) >= uint64(data.queue.len):
    return AccumulationQueueResult[ReadyItemInfo](status: AccumulationQueueError.InvalidIndex) # Bound conversion.
  let row = data.queue[int(uint64(index))]
  AccumulationQueueResult[ReadyItemInfo](status: AccumulationQueueError.None,
    completed: ReadyItemInfo(report: row.report, dependencies: row.dependencies.len))

proc accumulationDependencyAt*(plan: AccumulationQueuePlan, index: AccumulationIndex,
    dependency: WorkQueueHashIndex): AccumulationQueueResult[PackageHash] =
  ## Copy one dependency under its exact queue owner and nominal parent/member indices.
  let data = plan.data
  # A default handle owns no validated storage, even for an empty-looking extraction.
  if data == nil: return AccumulationQueueResult[PackageHash](
      status: AccumulationQueueError.Uninitialized)
  if uint64(index) >= uint64(data.queue.len):
    return AccumulationQueueResult[PackageHash](status: AccumulationQueueError.InvalidIndex) # Parent before child.
  let row = data.queue[int(uint64(index))]
  if uint64(dependency) >= uint64(row.dependencies.len):
    return AccumulationQueueResult[PackageHash](status: AccumulationQueueError.InvalidIndex) # Child before narrowing.
  AccumulationQueueResult[PackageHash](status: AccumulationQueueError.None,
    completed: row.dependencies[int(uint64(dependency))])

proc planAccumulationQueues*(available: openArray[OwnedReport],
    readyBytes: openArray[byte], accumulatedBytes: openArray[byte], slot: HeaderSlot,
    config: AccumulationQueueConfig): AccumulationQueueResult[AccumulationQueuePlan] =
  ## Pure projection from complete serialized parent C(14)/C(15), available reports and candidate time.
  ## Byte inputs are borrowed stably during this call, decoded/captured before use; no hashing or writes occur.
  ## Parent and incoming descriptors share explicit ceilings. Iterative Q bounds stack depth; unresolved cycles stop normally.
  template fail(reason: AccumulationQueueError) =
    return AccumulationQueueResult[AccumulationQueuePlan](status: reason)
  if uint64(config.queues.epochSlots) == 0 or uint64(config.queues.cores) < 2 or
      uint64(config.queues.cores) > 341:
    fail(AccumulationQueueError.InvalidConfig) # Reject unusable chain domains before applying byte ceilings.
  let maximum = uint64(config.items)
  let depMaximum = uint64(config.dependencies)
  if maximum > uint64(high(int) div sizeof(ReadyItem)) or
      depMaximum > uint64(high(int) div sizeof(PackageHash)):
    fail(AccumulationQueueError.InvalidConfig) # Prove native descriptor representation before allocation.
  if uint64(readyBytes.len) > uint64(config.queues.maxBytes) or
      uint64(accumulatedBytes.len) > uint64(config.queues.maxBytes):
    fail(AccumulationQueueError.LimitExceeded) # Bound serialized chapter capture first.
  let ready = decodeReadyState(readyBytes, config.queues)
  let accumulated = decodeAccumulatedState(accumulatedBytes, config.queues)
  # Both chapter decoders must complete before either captured owner is selected.
  for reason in [ready.error, accumulated.error]:
    case reason
    of WorkQueueError.None: discard # Complete owner available below.
    of WorkQueueError.InvalidConfig: fail(AccumulationQueueError.InvalidConfig) # Invalid chain/codec profile.
    of WorkQueueError.LimitExceeded, WorkQueueError.LengthOverflow:
      fail(AccumulationQueueError.LimitExceeded) # Preserve configured resource refusal.
    else: fail(AccumulationQueueError.InvalidState) # Malformed/default/truncated chapters cannot imply empty state.
  if ready.value.consumed != readyBytes.len or accumulated.value.consumed != accumulatedBytes.len:
    fail(AccumulationQueueError.InvalidState) # Chapters require exact consumption, not a valid prefix.
  let ri = readyInfo(ready.value.snapshot).value
  let ai = accumulatedInfo(accumulated.value.snapshot).value
  var count = uint64(ri.items)
  var deps = uint64(ri.dependencies)
  if count > maximum or uint64(ai.items) > maximum-count:
    fail(AccumulationQueueError.LimitExceeded) # Include historical hash descriptors in the shared item ceiling.
  count += uint64(ai.items)
  if uint64(available.len) > maximum-count or deps > depMaximum:
    fail(AccumulationQueueError.LimitExceeded) # Prove all later item additions and initial dependency copies.
  var bytes = 0'u64
  # Preflight every incoming owner and all aggregate extents before constructing D.
  for report in available:
    let info = ownedReportInfo(report)
    if info.error != OwnershipError.None:
      fail(AccumulationQueueError.InvalidReport) # Never dereference a missing report owner.
    let meta = info.value
    if uint64(meta.core) >= uint64(config.queues.cores) or
        uint64(meta.header.erasureShards) > uint64(config.queues.cores)*3:
      fail(AccumulationQueueError.InvalidReport) # Owners decoded under a larger profile cannot bypass this one.
    if uint64(meta.consumed) > uint64(config.queues.reportBytes) or
        uint64(meta.consumed) > uint64(config.queues.maxBytes)-bytes:
      fail(AccumulationQueueError.LimitExceeded) # Bound individual and total incoming wire retention.
    bytes += uint64(meta.consumed)
    let added = uint64(meta.prerequisiteCount)+uint64(meta.lookupCount)
    if added > depMaximum-deps:
      fail(AccumulationQueueError.LimitExceeded) # Conservative pre-union bound before building D.
    deps += added
  var history: seq[PackageHash] = @[]
  # Flatten history as a membership index; repeated hashes across slots remain harmless.
  for i in 0..<ai.slots:
    let length = accumulatedSlotCount(accumulated.value.snapshot, WorkQueueSlot(i)).value
    # Capture each fixed hash under the already validated accumulated slot.
    for j in 0..<length:
      history.add(accumulatedHashAt(accumulated.value.snapshot, WorkQueueSlot(i),
          WorkQueueHashIndex(j)).value)
  history.sort(compareHash) # Cross-slot duplicates are valid set-union evidence.
  var immediate: seq[OwnedReport] = @[]
  var immediateHashes: seq[PackageHash] = @[]
  var deferred: ReadyRow = @[]
  # Partition the original availability sequence without changing either subsequence order.
  for report in available:
    let meta = ownedReportInfo(report).value
    # Immediate means both dependency sources are empty, before history subtraction.
    if meta.prerequisiteCount == 0 and meta.lookupCount == 0:
      immediate.add(report)
      immediateHashes.add(meta.header.packageHash) # Preserve source order, including structurally allowed duplicates.
    else:
      # Deferred records retain their full report while D builds one dependency union.
      var row = ReadyItem(report: report, dependencies: @[])
      # Prerequisite fields are already a codec-validated set.
      for i in 0..<meta.prerequisiteCount: row.dependencies.add(ownedReportPrerequisite(report, i).value)
      # Add lookup keys once even when a prerequisite already names that identity.
      for i in 0..<meta.lookupCount:
        let key = ownedReportLookup(report, i).value.packageHash
        var present = false
        # At most the report codec's bounded dependency union needs checking here.
        for existing in row.dependencies:
          if compareHash(existing, key) == 0: present = true # D uses set union, not concatenation.
        if not present: row.dependencies.add(key) # Lookup roots never become dependency identities.
      row.dependencies.sort(compareHash)
      deferred.add(row)
  deferred = edit(deferred, history) # accumulatedcup applies only to newly deferred records here.
  var queue: ReadyRow = @[]
  let start = int(uint64(uint32(slot)) mod uint64(ri.slots))
  var position = start
  # Visit exactly one complete ring, starting at candidate time rather than parent time.
  for offset in 0..<ri.slots:
    let length = readySlotCount(ready.value.snapshot, WorkQueueSlot(position)).value
    # Preserve report order within each parent slot.
    for j in 0..<length:
      let row = readyItemAt(ready.value.snapshot, WorkQueueSlot(position), ReadyItemIndex(j)).value
      var item = ReadyItem(report: row.report, dependencies: @[])
      # Copy remaining dependencies; history subtraction is not specified for parent rows here.
      for k in 0..<row.dependencies:
        item.dependencies.add(readyDependencyAt(ready.value.snapshot, WorkQueueSlot(position),
          ReadyItemIndex(j), WorkQueueHashIndex(k)).value) # Preserve the parent's remaining dependency set verbatim.
      queue.add(item)
    inc position
    if position == ri.slots: position = 0 # Rotate without unchecked start+offset arithmetic.
  for row in deferred: queue.add(row) # Newly deferred reports follow every rotated parent row.
  immediateHashes.sort(compareHash)
  queue = edit(queue, immediateHashes)
  let data = QueueData(ready: ready.value.snapshot, accumulated: accumulated.value.snapshot,
    queue: queue, priority: immediate, immediate: immediate.len)
  var remaining = queue
  # Iterative Q avoids untrusted graph depth on the call stack.
  while remaining.len > 0:
    var wave: seq[PackageHash] = @[]
    # Scan all surviving rows before applying this wave's dependency removals.
    for row in remaining:
      # Only an empty remaining set makes a report ready in the current wave.
      if row.dependencies.len == 0:
        data.priority.add(row.report)
        wave.add(ownedReportInfo(row.report).value.header.packageHash) # Collect the whole wave before unlocking successors.
    if wave.len == 0: break # Cycles, self-dependencies and unavailable prerequisites are ordinary deferred work.
    wave.sort(compareHash)
    remaining = edit(remaining, wave) # Every nonempty wave removes at least one row, so iteration terminates.
  AccumulationQueueResult[AccumulationQueuePlan](status: AccumulationQueueError.None,
    completed: AccumulationQueuePlan(data: data))

proc planBlockAccumulationQueue*(reports: AdmittedReports,
    config: AccumulationQueueConfig): AccumulationQueueResult[BlockAccumulationQueue] =
  ## Derive exact parent chapters, availability output and candidate slot from genuine complete report admission.
  ## This read-only adapter cannot substitute loose reports or publish posterior history/queue state.
  template fail(reason: AccumulationQueueError) =
    return AccumulationQueueResult[BlockAccumulationQueue](status: reason)
  let stage = reports.reportBlockStage
  if stage.error != ReportAdmissionError.None:
    fail(AccumulationQueueError.InvalidAdmission) # No default/forged successful coordinator input.
  let profile = stage.value.blockTransitionProfile
  if uint64(profile.cores) != uint64(config.queues.cores) or
      uint64(profile.epochSlots) != uint64(config.queues.epochSlots):
    fail(AccumulationQueueError.InvalidConfig) # One authenticated block has one chain profile.
  let step = stage.value.value
  let parent = step.admitted.admittedState
  let ready = parent.lookup(chapterKey(StateChapter(14)))
  let accumulated = parent.lookup(chapterKey(StateChapter(15)))
  if ready.error == StateStoreError.MissingKey or accumulated.error == StateStoreError.MissingKey:
    fail(AccumulationQueueError.MissingState) # Missing chapters are never empty rings.
  if ready.error != StateStoreError.None or accumulated.error != StateStoreError.None:
    fail(AccumulationQueueError.InvalidState) # Retain complete parent-map semantics.
  if uint64(ready.value.byteLength) > uint64(config.queues.maxBytes) or
      uint64(accumulated.value.byteLength) > uint64(config.queues.maxBytes):
    fail(AccumulationQueueError.LimitExceeded) # Bound chapter copies before extracting mutable byte values.
  let length = step.availability.availableReportCount
  if uint64(length) > uint64(config.items):
    fail(AccumulationQueueError.LimitExceeded) # Bound incoming report descriptors before allocation.
  var available = newSeq[OwnedReport](length)
  for i in 0..<length: available[i] = step.availability.availableReportAt(
      i).value # Exact assurance-selected reports.
  let slot = headerInfo(step.admitted.admittedHeader).value.unsigned.slot
  let planned = planAccumulationQueues(available, ready.value.bytes, accumulated.value.bytes, slot, config)
  if planned.error != AccumulationQueueError.None:
    fail(planned.error) # No bound partial plan on downstream refusal.
  AccumulationQueueResult[BlockAccumulationQueue](status: AccumulationQueueError.None,
    completed: BlockAccumulationQueue(data: BlockQueueData(reports: reports, plan: planned.value)))

proc accumulationAdmission*(bound: BlockAccumulationQueue): AccumulationQueueResult[
    AdmittedReports] =
  ## Retain the exact completed admission source independently of caller scope.
  let data = bound.data
  # A default handle owns no validated storage, even for an empty-looking extraction.
  if data == nil: return AccumulationQueueResult[AdmittedReports](
      status: AccumulationQueueError.Uninitialized)
  AccumulationQueueResult[AdmittedReports](status: AccumulationQueueError.None,
      completed: data.reports)

proc accumulationProjection*(bound: BlockAccumulationQueue): AccumulationQueueResult[
    AccumulationQueuePlan] =
  ## Retain the derived pure priority projection; it does not certify report execution.
  let data = bound.data
  # A default handle owns no validated storage, even for an empty-looking extraction.
  if data == nil: return AccumulationQueueResult[AccumulationQueuePlan](
      status: AccumulationQueueError.Uninitialized)
  AccumulationQueueResult[AccumulationQueuePlan](status: AccumulationQueueError.None,
      completed: data.plan)
