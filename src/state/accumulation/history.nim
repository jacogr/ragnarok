# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shift accumulated-package C(15) once and append the finalized processed package set on a private full map.
## Provides a bounded pure ring projection and an opaque source-bound candidate; C(14)/whole-block publication remain separate.

import std/algorithm
import ../../codec/[bounded, owned, report_owned]
import ../../codec/work/report as work_report
import ../../codec/state/[workqueues as state_workqueues, layout as state_layout,
    trie as state_trie]
import ./[finalization as accumulation_finalization, outputs as accumulation_outputs,
    execution as accumulation_execution, round as accumulation_round, queue as accumulation_queue]
import ../report/admission as report_admission
import "../block/transition" as block_transition
import ../store

type
  AccumulationHistoryConfig* = object ## Work for supplied/processed report hashes is independent of input/output ring storage policy.
    reports*: ElementLimit ## Maximum hashes inspected before new-row sorting and deduplication.
    queues*: WorkQueueConfig ## Parent and posterior ring row/item/byte bounds with explicit core/epoch domains.
  AccumulationHistoryProjection* = object ## A pure projection owns independent canonical bytes and an immutable ring; it is not a block certificate.
    ring*: AccumulatedSnapshot ## Captured complete ring, independent of caller hashes and returned entry bytes.
    entry*: StateEntry ## Fresh C(15) bytes owned by this projection's caller.
  AccumulationHistoryInfo* = object ## Copied report progress and resulting history cardinalities never expose mutable ring storage.
    processedReports*: int ## Exact original-queue prefix, before package-set deduplication.
    newPackages*: int      ## Unique processed identities in the appended last row.
    slots*, packages*: int ## Fixed epoch row count and aggregate retained package count after shifting.
  AccumulationHistoryError* {.pure.} = enum ## Refusals carry only reasons, never source, projection or partially changed state.
    Uninitialized, ## Default result or candidate owner.
    None,          ## Selected complete success permits extraction.
    InvalidSource, ## No genuine finalized accumulation was supplied.
    InvalidConfig, ## Unsupported/mismatched core or epoch domains.
    InvalidState,  ## No valid complete accumulated snapshot or stored chapter.
    MissingState,  ## Required C(15) is absent rather than an initialized empty ring.
    LimitExceeded, ## Input work or native scratch exceeds the independent policy.
    CodecFailure,  ## Inspect the selected complete ring encoding/decoding reason.
    StateFailure   ## Inspect the selected private store refusal.
  # Acyclic private ownership binds canonical history bytes and immutable ring/map owners to exact finalization.
  AccumulationHistoryData = ref object
    source: PreparedFinalAccumulation
    projection: AccumulationHistoryProjection
    state: StateStoreSnapshot
    info: AccumulationHistoryInfo
  PreparedAccumulationHistory* = object ## Only authentic finalization authorizes this private full-state C(15) successor.
    data: nil AccumulationHistoryData
  AccumulationHistoryResult*[T] = object ## Only selected success carries values; defaults and all refusals retain reasons alone.
    case status: AccumulationHistoryError
    of None:
      completed: T # Success-guarded under checked optimized contracts.
    of CodecFailure:
      codecReason: WorkQueueError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # No fabricated empty ring or stale candidate is stored on failure.

func error*[T](outcome: AccumulationHistoryResult[T]): AccumulationHistoryError =
  ## Read the selected reason without permitting retagging.
  outcome.status

func value*[T](outcome: AccumulationHistoryResult[T]): T {.inline,
    requires: outcome.status == AccumulationHistoryError.None.} =
  ## Extract only selected complete success.
  outcome.completed

func codecError*[T](outcome: AccumulationHistoryResult[T]): WorkQueueError {.inline,
    requires: outcome.status == AccumulationHistoryError.CodecFailure.} =
  ## Inspect only a genuine ring codec refusal.
  outcome.codecReason

func stateError*[T](outcome: AccumulationHistoryResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationHistoryError.StateFailure.} =
  ## Inspect only a genuine private store refusal.
  outcome.stateReason

func compareHash(left, right: PackageHash): int =
  ## Package-set ordering compares every identity octet without interpreting hashes numerically.
  for index in 0..<32:
    if left.bytes[index] < right.bytes[index]: return -1
    if left.bytes[index] > right.bytes[index]: return 1
  0

proc projectAccumulationHistory*(parent: AccumulatedSnapshot, packages: openArray[PackageHash],
    config: AccumulationHistoryConfig): AccumulationHistoryResult[AccumulationHistoryProjection] =
  ## Shift an immutable ring once and append the sorted unique supplied identities; no hashes or state writes.
  ## Borrow package storage stably for this call and return independent entry bytes and a captured ring.
  template fail(reason: AccumulationHistoryError) =
    return AccumulationHistoryResult[AccumulationHistoryProjection](status: reason)
  let info = parent.accumulatedInfo
  if info.error != WorkQueueError.None:
    fail(AccumulationHistoryError.InvalidState) # Defaults never imply an empty initialized ring.
  if uint64(config.queues.cores) < 2 or uint64(config.queues.cores) > 341 or
      uint64(config.queues.epochSlots) == 0 or uint64(info.value.slots) != uint64(
          config.queues.epochSlots):
    fail(AccumulationHistoryError.InvalidConfig) # The captured ring belongs to exactly one fixed epoch shape.
  let slots = info.value.slots
  let maximum = high(int) div sizeof(PackageHash)
  if slots > high(int) div sizeof(AccumulatedRow) or uint64(slots) > uint64(config.queues.maxBytes):
    fail(AccumulationHistoryError.LimitExceeded) # Empty row framing and native descriptors are bounded before allocation.
  if uint64(packages.len) > uint64(config.reports) or packages.len > maximum or
      info.value.items > maximum-packages.len or uint64(info.value.items) > uint64(
          config.queues.totalItems):
    fail(AccumulationHistoryError.LimitExceeded) # Bound all input descriptors, including hashes in the dropped oldest row.
  for slot in 0..<slots:
    if uint64(parent.accumulatedSlotCount(WorkQueueSlot(uint64(slot))).value) > uint64(
        config.queues.perSlot):
      fail(AccumulationHistoryError.LimitExceeded) # A looser source capture cannot bypass the caller's input row policy.
  var newest = @packages
  newest.sort(compareHash)
  var unique = 0
  for index in 0..<newest.len:
    let hash = newest[index]
    if unique == 0 or compareHash(hash, newest[unique-1]) != 0:
      newest[unique] = hash
      inc unique # At most the already bounded number of inspected report hashes.
  var rows = newSeq[AccumulatedRow](slots)
  for slot in 0..<slots-1:
    let oldSlot = WorkQueueSlot(uint64(slot+1))
    let count = parent.accumulatedSlotCount(oldSlot).value
    rows[slot] = newSeq[PackageHash](count)
    for index in 0..<count:
      rows[slot][index] = parent.accumulatedHashAt(oldSlot, WorkQueueHashIndex(uint64(
          index))).value # Preserve earlier sets exactly.
  rows[slots-1] = newSeq[PackageHash](unique)
  for index in 0..<unique: rows[slots-1][index] = newest[index] # Retain only unique new-row members.
  let encoded = accumulatedStateEntry(rows, config.queues)
  if encoded.error != WorkQueueError.None:
    return AccumulationHistoryResult[AccumulationHistoryProjection](
      status: AccumulationHistoryError.CodecFailure,
      codecReason: encoded.error) # Existing codec preflights all output extents before byte allocation.
  let captured = decodeAccumulatedState(encoded.value.value, config.queues)
  if captured.error != WorkQueueError.None:
    return AccumulationHistoryResult[AccumulationHistoryProjection](
      status: AccumulationHistoryError.CodecFailure,
      codecReason: captured.error) # Only complete immutable capture authorizes a projection.
  AccumulationHistoryResult[AccumulationHistoryProjection](status: AccumulationHistoryError.None,
    completed: AccumulationHistoryProjection(ring: captured.value.snapshot, entry: encoded.value))

proc accumulationHistoryInfo*(plan: PreparedAccumulationHistory): AccumulationHistoryResult[
    AccumulationHistoryInfo] =
  ## Copy processed/new/retained counts without exposing mutable history storage.
  let data = plan.data
  if data == nil:
    return AccumulationHistoryResult[AccumulationHistoryInfo](
        status: AccumulationHistoryError.Uninitialized) # Default owners are not empty history updates.
  AccumulationHistoryResult[AccumulationHistoryInfo](status: AccumulationHistoryError.None,
      completed: data.info)

proc accumulationHistorySource*(plan: PreparedAccumulationHistory): AccumulationHistoryResult[
    PreparedFinalAccumulation] =
  ## Retain the exact finalization and its service/output state provenance.
  let data = plan.data
  if data == nil:
    return AccumulationHistoryResult[PreparedFinalAccumulation](
        status: AccumulationHistoryError.Uninitialized) # No synthetic finalized source.
  AccumulationHistoryResult[PreparedFinalAccumulation](status: AccumulationHistoryError.None,
      completed: data.source)

proc accumulationHistoryRing*(plan: PreparedAccumulationHistory): AccumulationHistoryResult[
    AccumulatedSnapshot] =
  ## Retain the immutable complete posterior ring for existing nominal slot/hash accessors.
  let data = plan.data
  if data == nil:
    return AccumulationHistoryResult[AccumulatedSnapshot](
        status: AccumulationHistoryError.Uninitialized) # No fabricated ring.
  AccumulationHistoryResult[AccumulatedSnapshot](status: AccumulationHistoryError.None,
      completed: data.projection.ring)

proc accumulationHistoryState*(plan: PreparedAccumulationHistory): AccumulationHistoryResult[
    StateStoreSnapshot] =
  ## Retain the full-map candidate after C(15), preserving C(16) and all earlier service state.
  let data = plan.data
  if data == nil:
    return AccumulationHistoryResult[StateStoreSnapshot](
        status: AccumulationHistoryError.Uninitialized) # Partial/default maps cannot be returned as full state.
  AccumulationHistoryResult[StateStoreSnapshot](status: AccumulationHistoryError.None,
      completed: data.state)

proc accumulationHistoryEntry*(plan: PreparedAccumulationHistory): AccumulationHistoryResult[StateEntry] =
  ## Copy fresh canonical C(15) bytes; changing the returned entry cannot mutate retained history or state.
  let data = plan.data
  if data == nil:
    return AccumulationHistoryResult[StateEntry](status: AccumulationHistoryError.Uninitialized) # No fabricated empty encoding.
  let entry = data.projection.entry
  var bytes = newSeq[byte](entry.value.len)
  for index in 0..<bytes.len: bytes[index] = entry.value[index] # Independent mutable extraction storage.
  AccumulationHistoryResult[StateEntry](status: AccumulationHistoryError.None,
    completed: StateEntry(key: entry.key, value: bytes))

proc prepareAccumulationHistory*(source: PreparedFinalAccumulation,
    config: AccumulationHistoryConfig): AccumulationHistoryResult[PreparedAccumulationHistory] =
  ## Derive exact processed identities and C(15) from genuine finalization, then update only a private full-state fork.
  let finalized = source.finalAccumulationInfo
  if finalized.error != AccumulationFinalizationError.None:
    return AccumulationHistoryResult[PreparedAccumulationHistory](
        status: AccumulationHistoryError.InvalidSource) # No work on default sources.
  let bound = source.finalAccumulationQueue.value
  let profile = bound.accumulationAdmission.value.reportBlockStage.value.blockTransitionProfile
  if uint64(profile.cores) != uint64(config.queues.cores) or uint64(profile.epochSlots) != uint64(
      config.queues.epochSlots):
    return AccumulationHistoryResult[PreparedAccumulationHistory](
        status: AccumulationHistoryError.InvalidConfig) # One authenticated block has one chain profile.
  let processed = uint64(finalized.value.completedPrefix)
  if processed > uint64(config.reports) or processed > uint64(high(int) div sizeof(PackageHash)):
    return AccumulationHistoryResult[PreparedAccumulationHistory](
        status: AccumulationHistoryError.LimitExceeded) # Bound traversal/storage before copying identities.
  let prior = source.finalAccumulationState.value
  let stored = prior.lookup(chapterKey(StateChapter(15)))
  if stored.error == StateStoreError.MissingKey:
    return AccumulationHistoryResult[PreparedAccumulationHistory](
        status: AccumulationHistoryError.MissingState) # Missing is never an initialized empty ring.
  if stored.error != StateStoreError.None:
    return AccumulationHistoryResult[PreparedAccumulationHistory](
        status: AccumulationHistoryError.InvalidState) # Require complete-map source access.
  if uint64(stored.value.byteLength) > uint64(config.queues.maxBytes):
    return AccumulationHistoryResult[PreparedAccumulationHistory](
        status: AccumulationHistoryError.LimitExceeded) # Check before copying stored chapter bytes.
  let bytes = stored.value.bytes
  let parent = decodeAccumulatedState(bytes, config.queues)
  if parent.error != WorkQueueError.None:
    return AccumulationHistoryResult[PreparedAccumulationHistory](
      status: AccumulationHistoryError.CodecFailure,
      codecReason: parent.error) # No candidate after malformed or over-budget parent capture.
  if parent.value.consumed != bytes.len:
    return AccumulationHistoryResult[PreparedAccumulationHistory](
        status: AccumulationHistoryError.InvalidState) # Stored chapters require exact consumption.
  let queue = bound.accumulationProjection.value
  var packages = newSeq[PackageHash](int(processed))
  for index in 0..<packages.len:
    packages[index] = queue.accumulationAt(AccumulationIndex(uint64(
        index))).value.ownedReportInfo.value.header.packageHash # Original admitted queue only.
  let projected = projectAccumulationHistory(parent.value.snapshot, packages, config)
  if projected.error == AccumulationHistoryError.CodecFailure:
    return AccumulationHistoryResult[PreparedAccumulationHistory](
      status: AccumulationHistoryError.CodecFailure,
      codecReason: projected.codecError) # Preserve only the selected nested codec reason.
  if projected.error != AccumulationHistoryError.None:
    return AccumulationHistoryResult[PreparedAccumulationHistory](
        status: projected.error) # Other failures contain reasons alone.
  var working = forkStateStore(prior).value # Genuine finalization retains a complete initialized map and inherited ceilings.
  let applied = working.apply([StateWrite(key: projected.value.entry.key, kind: StateWriteKind.Put,
    value: projected.value.entry.value)])
  if applied.error != StateStoreError.None:
    return AccumulationHistoryResult[PreparedAccumulationHistory](
      status: AccumulationHistoryError.StateFailure,
      stateReason: applied.error) # Drop the private candidate; all priors remain unchanged.
  let ring = projected.value.ring
  let info = ring.accumulatedInfo.value
  AccumulationHistoryResult[PreparedAccumulationHistory](status: AccumulationHistoryError.None,
    completed: PreparedAccumulationHistory(data: AccumulationHistoryData(source: source,
      projection: projected.value, state: applied.value, info: AccumulationHistoryInfo(
        processedReports: packages.len, newPackages: ring.accumulatedSlotCount(WorkQueueSlot(uint64(
            info.slots-1))).value,
        slots: info.slots, packages: info.items))))
