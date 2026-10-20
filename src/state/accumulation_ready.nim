# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 accumulation.tex final ready equation: expire crossed rows and edit only by processed packages.
## Pure projection and source-bound private C(14) successor preserve finalized C(15)/C(16) and service state.

import std/algorithm
import ../codec/[natural, bounded, owned, report_owned, work_report, header, state_workqueues,
    state_layout, state_trie]
import ./[accumulation_history, accumulation_finalization, accumulation_outputs,
  accumulation_execution,
  accumulation_round, accumulation_queue, report_admission, block_transition, block_admission,
  availability, store]

type
  AccumulationReadyConfig* = object ## Independent input-work ceilings apply before expiry/removal can shrink output.
    items*, dependencies*: ElementLimit ## Combined parent/incoming reports, history/processed hashes and dependency work.
    queues*: WorkQueueConfig ## Per-row, aggregate, report and complete wire policies for both input and output.
  AccumulationReadyProjection* = object ## Caller-owned entry bytes and an independently captured immutable ready ring.
    ring*: ReadySnapshot ## Complete posterior C(14), never a block execution certificate by itself.
    entry*: StateEntry   ## Fresh canonical bytes independent of ring storage.
  AccumulationReadyError* {.pure.} = enum ## Refusals contain reasons alone and no partial queue or map.
    Uninitialized, None, InvalidSource, InvalidConfig, InvalidState, InvalidReport, InvalidTime,
    MissingState, LimitExceeded, CodecFailure, StateFailure
  ReadyData = ref object # Acyclic immutable ownership retains exact C(15) predecessor and full private successor.
    source: PreparedAccumulationHistory
    projection: AccumulationReadyProjection
    state: StateStoreSnapshot
  PreparedAccumulationReady* = object ## Only finalized accumulated history can authorize a bound successor.
    data: nil ReadyData
  AccumulationReadyResult*[T] = object ## Payloads exist only under selected success; nested errors are guarded.
    case status: AccumulationReadyError
    of None:
      completed: T # No success payload on default/refusal.
    of CodecFailure:
      codecReason: WorkQueueError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # No fabricated empty queue or partial candidate.

func error*[T](outcome: AccumulationReadyResult[T]): AccumulationReadyError =
  ## Read a reason without exposing the discriminator to writes.
  outcome.status
func value*[T](outcome: AccumulationReadyResult[T]): T {.inline,
    requires: outcome.status == AccumulationReadyError.None.} =
  ## Extract only selected complete success.
  outcome.completed
func codecError*[T](outcome: AccumulationReadyResult[T]): WorkQueueError {.inline,
    requires: outcome.status == AccumulationReadyError.CodecFailure.} =
  ## Read only a selected codec refusal.
  outcome.codecReason
func stateError*[T](outcome: AccumulationReadyResult[T]): StateStoreError {.inline,
    requires: outcome.status == AccumulationReadyError.StateFailure.} =
  ## Read only a selected private store refusal.
  outcome.stateReason

# Hash ordering and binary membership operate in the package domain, without hashing or numeric conversion.
func compareHash(left, right: PackageHash): int =
  for index in 0..<32:
    if left.bytes[index] < right.bytes[index]: return -1
    if left.bytes[index] > right.bytes[index]: return 1
  0

func contains(hashes: seq[PackageHash], key: PackageHash): bool =
  ## Search bounded sorted scratch, including harmless cross-row history duplicates.
  var first = 0
  var last = hashes.len
  while first < last:
    let middle = first+(last-first) div 2
    if compareHash(hashes[middle], key) < 0:
      first = middle+1 # Discard only identities proved smaller.
    else:
      last = middle # Retain the first possible matching identity.
  first < hashes.len and compareHash(hashes[first], key) == 0

proc projectAccumulationReady*(parent: ReadySnapshot, accumulated: AccumulatedSnapshot,
    available: openArray[OwnedReport], processed: openArray[PackageHash],
    parentSlot, candidateSlot: HeaderSlot, config: AccumulationReadyConfig):
    AccumulationReadyResult[AccumulationReadyProjection] =
  ## Apply the final ready equation to explicit stable inputs; no writes, hashes or execution certification.
  ## Parent/history and incoming work are bounded in full before expiry or dependency subtraction.
  template fail(reason: AccumulationReadyError) =
    return AccumulationReadyResult[AccumulationReadyProjection](status: reason)
  let ri = parent.readyInfo
  let ai = accumulated.accumulatedInfo
  if ri.error != WorkQueueError.None or ai.error != WorkQueueError.None:
    fail(AccumulationReadyError.InvalidState) # Default snapshots never imply initialized empty rings.
  let queues = config.queues
  if uint64(queues.cores) < 2 or uint64(queues.cores) > 341 or uint64(queues.epochSlots) == 0 or
      uint64(ri.value.slots) != uint64(queues.epochSlots) or ai.value.slots != ri.value.slots:
    fail(AccumulationReadyError.InvalidConfig) # Both rings and reports share the exact chain profile.
  if uint32(candidateSlot) <= uint32(parentSlot):
    fail(AccumulationReadyError.InvalidTime) # Prove subtraction without slot wrapping.
  let slots = ri.value.slots
  if slots > high(int) div sizeof(ReadyRow) or uint64(slots) > uint64(queues.maxBytes):
    fail(AccumulationReadyError.LimitExceeded) # Bound even empty ring descriptors/framing.
  var items = 0'u64
  for count in [ri.value.items, ai.value.items, available.len, processed.len]:
    if uint64(count) > uint64(config.items)-items or count > high(int) div max(sizeof(ReadyItem),
        sizeof(PackageHash)):
      fail(AccumulationReadyError.LimitExceeded) # Subtract before adding each input-work charge.
    items += uint64(count)
  if ri.value.items > high(int) div sizeof(ReadyItem) or
      ri.value.dependencies > high(int) div sizeof(PackageHash) or
      uint64(ri.value.items) > uint64(queues.totalItems) or
      uint64(ai.value.items) > uint64(queues.totalItems):
    fail(AccumulationReadyError.LimitExceeded) # Include expired history and parent rows in input policies.
  var dependencies = uint64(ri.value.dependencies)
  if dependencies > uint64(config.dependencies) or dependencies > uint64(queues.totalDependencies):
    fail(AccumulationReadyError.LimitExceeded) # Parent dependencies count before any removal.
  var reportBytes = 0'u64
  var readyBytes = 0'u64
  var historyBytes = 0'u64
  template chargeWire(total: var uint64, count: uint64) =
    # Count framing, fixed hashes and report wire all share the complete input chapter policy.
    if count > uint64(queues.maxBytes)-total or count > uint64(high(int))-total:
      fail(AccumulationReadyError.LimitExceeded)
    total += count
  for slot in 0..<slots:
    let position = WorkQueueSlot(uint64(slot))
    let count = parent.readySlotCount(position).value
    let historyCount = accumulated.accumulatedSlotCount(position).value
    if historyCount > high(int) div sizeof(PackageHash):
      fail(AccumulationReadyError.LimitExceeded) # Prove native history storage before fixed-width multiplication.
    chargeWire(readyBytes, uint64(natural.encode(JamNatural(uint64(count))).len))
    chargeWire(historyBytes, uint64(natural.encode(JamNatural(uint64(historyCount))).len))
    if uint64(historyCount) > (uint64(queues.maxBytes)-historyBytes) div 32:
      fail(AccumulationReadyError.LimitExceeded) # Prove wire multiplication before charging fixed hashes.
    chargeWire(historyBytes, uint64(historyCount)*32)
    if uint64(count) > uint64(queues.perSlot) or
        uint64(accumulated.accumulatedSlotCount(position).value) > uint64(queues.perSlot):
      fail(AccumulationReadyError.LimitExceeded) # A looser source capture cannot bypass row ceilings.
    for index in 0..<count:
      let item = parent.readyItemAt(position, ReadyItemIndex(uint64(index))).value
      let meta = item.report.ownedReportInfo.value
      if uint64(meta.core) >= uint64(queues.cores) or uint64(meta.header.erasureShards) > uint64(
          queues.cores)*3:
        fail(AccumulationReadyError.InvalidReport) # Check report domains even for rows that will expire.
      if uint64(item.dependencies) > uint64(queues.perDependencies) or
          uint64(meta.consumed) > uint64(queues.reportBytes) or
          uint64(meta.consumed) > uint64(queues.maxBytes)-reportBytes:
        fail(AccumulationReadyError.LimitExceeded) # Bound retained report wire work before copying descriptors.
      reportBytes += uint64(meta.consumed)
      chargeWire(readyBytes, uint64(meta.consumed))
      chargeWire(readyBytes, uint64(natural.encode(JamNatural(uint64(item.dependencies))).len))
      if uint64(item.dependencies) > (uint64(queues.maxBytes)-readyBytes) div 32:
        fail(AccumulationReadyError.LimitExceeded) # Bound dependency wire even when this row expires.
      chargeWire(readyBytes, uint64(item.dependencies)*32)
  for report in available:
    let info = report.ownedReportInfo
    if info.error != OwnershipError.None: fail(AccumulationReadyError.InvalidReport) # No default report metadata access.
    let meta = info.value
    if uint64(meta.core) >= uint64(queues.cores) or uint64(meta.header.erasureShards) > uint64(
        queues.cores)*3:
      fail(AccumulationReadyError.InvalidReport) # Recheck owners captured under larger profiles.
    let count = uint64(meta.prerequisiteCount)+uint64(meta.lookupCount)
    if count > uint64(config.dependencies)-dependencies or
        count > uint64(high(int) div sizeof(PackageHash)):
      fail(AccumulationReadyError.LimitExceeded) # Bound dependency-union scratch before allocation.
    if uint64(meta.consumed) > uint64(queues.reportBytes) or
        uint64(meta.consumed) > uint64(queues.maxBytes)-reportBytes:
      fail(AccumulationReadyError.LimitExceeded) # Incoming and parent report wire share a work ceiling.
    dependencies += count
    if dependencies > uint64(high(int) div sizeof(PackageHash)):
      fail(AccumulationReadyError.LimitExceeded) # Combined dependency scratch must fit native storage.
    reportBytes += uint64(meta.consumed)
  var history: seq[PackageHash] = @[]
  for slot in 0..<slots:
    let position = WorkQueueSlot(uint64(slot))
    for index in 0..<accumulated.accumulatedSlotCount(position).value:
      history.add(accumulated.accumulatedHashAt(position, WorkQueueHashIndex(uint64(index))).value)
  history.sort(compareHash) # Historical union applies to newly available deferred reports only.
  var selected = @processed
  selected.sort(compareHash) # Only actually processed packages remove old queued rows/dependencies.
  var rows = newSeq[ReadyRow](slots)
  let current = int(uint64(uint32(candidateSlot)) mod uint64(slots))
  let elapsed = uint64(uint32(candidateSlot))-uint64(uint32(parentSlot))
  var position = current
  for age in 0..<slots:
    if age > 0 and uint64(age) >= elapsed:
      let slot = WorkQueueSlot(uint64(position))
      for index in 0..<parent.readySlotCount(slot).value:
        let item = parent.readyItemAt(slot, ReadyItemIndex(uint64(index))).value
        if not selected.contains(item.report.ownedReportInfo.value.header.packageHash):
          var retained = ReadyItem(report: item.report, dependencies: @[])
          for dependency in 0..<item.dependencies:
            let hash = parent.readyDependencyAt(slot, ReadyItemIndex(uint64(index)),
              WorkQueueHashIndex(uint64(dependency))).value
            if not selected.contains(hash): retained.dependencies.add(
                hash) # E preserves all unsatisfied dependencies.
          rows[position].add(retained) # Preserve report order, including structurally allowed duplicate identities.
    if position == 0: position = slots-1
    else: dec position # Cyclic m-i without unsigned underflow.
  for report in available:
    let meta = report.ownedReportInfo.value
    if meta.prerequisiteCount > 0 or meta.lookupCount > 0:
      if not history.contains(meta.header.packageHash) and not selected.contains(
          meta.header.packageHash):
        var hashes: seq[PackageHash] = @[]
        for index in 0..<meta.prerequisiteCount: hashes.add(report.ownedReportPrerequisite(index).value)
        for index in 0..<meta.lookupCount: hashes.add(report.ownedReportLookup(
            index).value.packageHash)
        hashes.sort(compareHash) # D uses a set union; lookup roots never become dependency identities.
        var retained = ReadyItem(report: report, dependencies: @[])
        for hash in hashes:
          if not history.contains(hash) and not selected.contains(hash):
            if retained.dependencies.len == 0 or compareHash(retained.dependencies[^1], hash) != 0:
              retained.dependencies.add(hash) # Canonical sorted union after both E applications.
        rows[current].add(retained) # Replace current row with deferred availability, never immediate reports or flattened q.
  let encoded = readyStateEntry(rows, queues)
  if encoded.error != WorkQueueError.None:
    return AccumulationReadyResult[AccumulationReadyProjection](
      status: AccumulationReadyError.CodecFailure,
      codecReason: encoded.error) # Codec preflights complete framing and output policies before byte allocation.
  let captured = decodeReadyState(encoded.value.value, queues)
  if captured.error != WorkQueueError.None:
    return AccumulationReadyResult[AccumulationReadyProjection](
      status: AccumulationReadyError.CodecFailure,
      codecReason: captured.error) # Return only a completely captured immutable posterior.
  AccumulationReadyResult[AccumulationReadyProjection](status: AccumulationReadyError.None,
    completed: AccumulationReadyProjection(ring: captured.value.snapshot, entry: encoded.value))

proc accumulationReadySource*(plan: PreparedAccumulationReady): AccumulationReadyResult[
    PreparedAccumulationHistory] =
  ## Retain the exact history/finalization source independently of caller lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationReadyResult[PreparedAccumulationHistory](
        status: AccumulationReadyError.Uninitialized)
  AccumulationReadyResult[PreparedAccumulationHistory](status: AccumulationReadyError.None,
      completed: data.source)

proc accumulationReadyRing*(plan: PreparedAccumulationReady): AccumulationReadyResult[
    ReadySnapshot] =
  ## Retain immutable complete posterior C(14).
  let data = plan.data
  if data == nil:
    return AccumulationReadyResult[ReadySnapshot](status: AccumulationReadyError.Uninitialized)
  AccumulationReadyResult[ReadySnapshot](status: AccumulationReadyError.None,
      completed: data.projection.ring)

proc accumulationReadyState*(plan: PreparedAccumulationReady): AccumulationReadyResult[
    StateStoreSnapshot] =
  ## Retain the complete private successor, including earlier service/C(15)/C(16) effects.
  let data = plan.data
  if data == nil:
    return AccumulationReadyResult[StateStoreSnapshot](status: AccumulationReadyError.Uninitialized)
  AccumulationReadyResult[StateStoreSnapshot](status: AccumulationReadyError.None,
      completed: data.state)

proc accumulationReadyEntry*(plan: PreparedAccumulationReady): AccumulationReadyResult[StateEntry] =
  ## Extract independent bytes so callers cannot mutate the retained ring or state.
  let data = plan.data
  if data == nil:
    return AccumulationReadyResult[StateEntry](status: AccumulationReadyError.Uninitialized)
  let entry = data.projection.entry
  var bytes = newSeq[byte](entry.value.len)
  for index in 0..<bytes.len: bytes[index] = entry.value[index] # Copy only the bounded retained entry.
  AccumulationReadyResult[StateEntry](status: AccumulationReadyError.None,
    completed: StateEntry(key: entry.key, value: bytes))

proc prepareAccumulationReady*(source: PreparedAccumulationHistory,
    config: AccumulationReadyConfig): AccumulationReadyResult[PreparedAccumulationReady] =
  ## Derive original rings, availability, time and exact processed set from one certified history source.
  template fail(reason: AccumulationReadyError) =
    return AccumulationReadyResult[PreparedAccumulationReady](status: reason)
  let finalized = source.accumulationHistorySource
  if finalized.error != AccumulationHistoryError.None:
    fail(AccumulationReadyError.InvalidSource) # Defaults cannot fabricate block provenance.
  let bound = finalized.value.finalAccumulationOutputs.value.outputsSource.value.executionRound.value.roundBlockQueue.value
  let stage = bound.accumulationAdmission.value.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  if uint64(profile.cores) != uint64(config.queues.cores) or
      uint64(profile.epochSlots) != uint64(config.queues.epochSlots):
    fail(AccumulationReadyError.InvalidConfig) # Reject mismatched profiles before any chapter copies.
  let step = stage.value
  let parent = step.admitted.admittedState
  let ready = parent.lookup(chapterKey(StateChapter(14)))
  let accumulated = parent.lookup(chapterKey(StateChapter(15)))
  if ready.error == StateStoreError.MissingKey or accumulated.error == StateStoreError.MissingKey:
    fail(AccumulationReadyError.MissingState) # Never replace absent chapters with empty rings.
  if ready.error != StateStoreError.None or accumulated.error != StateStoreError.None:
    fail(AccumulationReadyError.InvalidState) # Require complete parent access.
  if uint64(ready.value.byteLength) > uint64(config.queues.maxBytes) or
      uint64(accumulated.value.byteLength) > uint64(config.queues.maxBytes):
    fail(AccumulationReadyError.LimitExceeded) # Bound stored-byte copies first.
  let readyBytes = ready.value.bytes
  let accumulatedBytes = accumulated.value.bytes
  let decodedReady = decodeReadyState(readyBytes, config.queues)
  let decodedAccumulated = decodeAccumulatedState(accumulatedBytes, config.queues)
  for reason in [decodedReady.error, decodedAccumulated.error]:
    if reason != WorkQueueError.None:
      return AccumulationReadyResult[PreparedAccumulationReady](
        status: AccumulationReadyError.CodecFailure,
        codecReason: reason) # Failed chapter capture never authorizes partial projection.
  if decodedReady.value.consumed != readyBytes.len or decodedAccumulated.value.consumed !=
      accumulatedBytes.len:
    fail(AccumulationReadyError.InvalidState) # Chapter prefixes with trailing bytes are invalid.
  let count = step.availability.availableReportCount
  let ring = source.accumulationHistoryRing.value
  let last = WorkQueueSlot(uint64(profile.epochSlots)-1)
  let processedCount = ring.accumulatedSlotCount(last).value
  if uint64(count) > uint64(config.items):
    fail(AccumulationReadyError.LimitExceeded) # Bound availability traversal before allocation.
  if uint64(processedCount) > uint64(config.items)-uint64(count):
    fail(AccumulationReadyError.LimitExceeded) # Charge the certified processed set without overflow.
  if count > high(int) div sizeof(OwnedReport) or processedCount > high(int) div sizeof(PackageHash):
    fail(AccumulationReadyError.LimitExceeded) # Bound native adapter descriptors before allocation.
  var available = newSeq[OwnedReport](count)
  for index in 0..<count: available[index] = step.availability.availableReportAt(index).value
  var processed = newSeq[PackageHash](processedCount)
  for index in 0..<processedCount: processed[index] = ring.accumulatedHashAt(last,
      WorkQueueHashIndex(uint64(index))).value
  let projected = projectAccumulationReady(decodedReady.value.snapshot,
    decodedAccumulated.value.snapshot,
    available, processed, headerInfo(step.admitted.admittedParent).value.unsigned.slot,
    headerInfo(step.admitted.admittedHeader).value.unsigned.slot, config)
  if projected.error == AccumulationReadyError.CodecFailure:
    return AccumulationReadyResult[PreparedAccumulationReady](
      status: AccumulationReadyError.CodecFailure,
      codecReason: projected.codecError) # Preserve only selected nested reasons.
  if projected.error != AccumulationReadyError.None: fail(
      projected.error) # No private map work after pure refusal.
  var working = forkStateStore(source.accumulationHistoryState.value).value
  let applied = working.apply([StateWrite(key: projected.value.entry.key, kind: StateWriteKind.Put,
    value: projected.value.entry.value)])
  if applied.error != StateStoreError.None:
    return AccumulationReadyResult[PreparedAccumulationReady](
      status: AccumulationReadyError.StateFailure,
      stateReason: applied.error) # Private failure leaves caller and every predecessor untouched.
  AccumulationReadyResult[PreparedAccumulationReady](status: AccumulationReadyError.None,
    completed: PreparedAccumulationReady(data: ReadyData(source: source,
        projection: projected.value, state: applied.value)))
