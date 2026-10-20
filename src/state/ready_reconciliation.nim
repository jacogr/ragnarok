# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reconcile C(14) using newly deferred reports, actual processed packages and elapsed-slot expiry.
## Original parent context comes from the exact coordinated accumulation source; publication preserves its complete successor.

import std/algorithm
import ../codec/[bounded, owned, report_owned, work_report, header, state_safrole,
  state_workqueues, state_layout, state_trie]
import ./[accumulation_publication, block_activity, service_activity, accumulation_statistics,
  accumulation_finalization, accumulation_outputs, accumulation_execution, accumulation_round,
  accumulation_queue, report_admission, block_transition, block_admission, availability, store]

type
  ReadyReconciliationConfig* = object ## Inspected work is independent of canonical output row/item/dependency/byte policy.
    reports*, dependencies*, historyHashes*, processed*: ElementLimit
    queues*: WorkQueueConfig
  ReadyReconciliationInfo* = object ## Copied input/output populations and elapsed expiry observations.
    available*, processed*, expiredRows*, slots*, reports*, dependencies*: int
  ReadyReconciliationProjection* = object ## Raw-input rows/bytes are not an admission or execution certificate.
    info*: ReadyReconciliationInfo
    entry*: StateEntry
    queue*: ReadySnapshot
  ReadyReconciliationError* {.pure.} = enum ## Defaults/refusals contain only selected reasons, never partial queue/state.
    Uninitialized, ## Default owner or result.
    None,          ## Complete selected success.
    InvalidSource, ## No genuine coordinated accumulation successor.
    InvalidConfig, ## Core/epoch profile is unsupported or mismatched.
    InvalidInput,  ## Default owner or report outside the selected profile.
    InvalidState,  ## Missing exact decoded original chapter/store context.
    InvalidSlot,   ## Target time must strictly follow parent time.
    ForeignState,  ## Mutable caller is not the exact coordinated prior.
    LimitExceeded, ## Inspected work/capture/native extent exceeds policy.
    CodecFailure,  ## Inspect canonical queue input/output codec refusal.
    StateFailure   ## Inspect atomic store/backend refusal.
  ReadyData = ref object # Acyclic storage retains exact source/prior and independent projected bytes/ring.
    source: PublishedAccumulation
    prior: StateStoreSnapshot
    projection: ReadyReconciliationProjection
  PreparedReadyReconciliation* = object ## Only genuine coordinated accumulation authorizes this scoped successor step.
    data: nil ReadyData
  PublishedData = ref object # Retained complete successor never aliases a mutable caller store.
    source: PreparedReadyReconciliation
    state: StateStoreSnapshot
  PublishedReadyReconciliation* = object ## Queue publication leaves recent-history/remaining whole-block stages open.
    data: nil PublishedData
  ReadyReconciliationResult*[T] = object ## Private alternatives guard every application payload and nested reason.
    case status: ReadyReconciliationError
    of None:
      completed: T # Only complete success carries output.
    of CodecFailure:
      codecReason: WorkQueueError
    of StateFailure:
      stateReason: StateStoreError
    else:
      discard      # Default/failed alternatives cannot fabricate empty queues or partial maps.

func error*[T](outcome: ReadyReconciliationResult[T]): ReadyReconciliationError =
  ## Inspect the immutable selected reason.
  outcome.status
func value*[T](outcome: ReadyReconciliationResult[T]): T {.inline,
    requires: outcome.status == ReadyReconciliationError.None.} =
  ## Extract only complete selected success in checked optimized builds.
  outcome.completed
func codecError*[T](outcome: ReadyReconciliationResult[T]): WorkQueueError {.inline,
    requires: outcome.status == ReadyReconciliationError.CodecFailure.} =
  ## Inspect only an actual selected queue codec refusal.
  outcome.codecReason
func stateError*[T](outcome: ReadyReconciliationResult[T]): StateStoreError {.inline,
    requires: outcome.status == ReadyReconciliationError.StateFailure.} =
  ## Inspect only a genuine atomic publication refusal.
  outcome.stateReason
func compareHash(left, right: PackageHash): int =
  ## Compare every fixed hash octet in canonical set order.
  for index in 0..<32:
    if left.bytes[index] < right.bytes[index]: return -1
    if left.bytes[index] > right.bytes[index]: return 1
  0
func contains(hashes: seq[PackageHash], hash: PackageHash): bool =
  ## Binary membership in bounded sorted scratch; duplicate input hashes have set semantics.
  var first = 0
  var last = hashes.len
  while first < last:
    let middle = first+(last-first) div 2
    let order = compareHash(hashes[middle], hash)
    if order == 0: return true # A single matching identity satisfies membership.
    if order < 0: first = middle+1 # Native difference arithmetic proves midpoint/increment safe.
    else: last = middle # Preserve the lower half without unchecked addition.
  false
proc charge(total: var int, count: int, limit: ElementLimit, width: int): bool =
  ## Prove combined nonnegative inspected descriptors before addition/allocation.
  if uint64(count) > uint64(limit)-uint64(total) or count > high(int) div width-total: return false
  total += count
  true
proc edited(report: OwnedReport, dependencies: seq[PackageHash], processed: seq[
    PackageHash]): ReadyItem =
  ## Retain one surviving report and copy only unsatisfied dependencies in their original canonical order.
  result = ReadyItem(report: report, dependencies: @[])
  for hash in dependencies:
    if not processed.contains(hash): result.dependencies.add(
        hash) # E removes satisfied dependencies without reordering survivors.

proc projectReadyReconciliation*(parent: ReadySnapshot, history: AccumulatedSnapshot,
    available: openArray[OwnedReport], processed: openArray[PackageHash],
    previousTime, target: StateTime, config: ReadyReconciliationConfig): ReadyReconciliationResult[
        ReadyReconciliationProjection] =
  ## Borrow stable raw inputs; use the original accumulated union only for newly deferred D/E, never for old parent rows.
  template fail(reason: ReadyReconciliationError) =
    ## Discard all private scratch and expose no partially reconciled row.
    return ReadyReconciliationResult[ReadyReconciliationProjection](status: reason)
  let old = parent.readyInfo
  let accumulated = history.accumulatedInfo
  if old.error != WorkQueueError.None or accumulated.error != WorkQueueError.None: fail(
      ReadyReconciliationError.InvalidInput)
  let slots = old.value.slots
  if uint64(config.queues.cores) < 2 or uint64(config.queues.cores) > 341 or
      uint64(config.queues.epochSlots) == 0 or uint64(slots) != uint64(config.queues.epochSlots) or
          accumulated.value.slots != slots:
    fail(ReadyReconciliationError.InvalidConfig)
  let shardCeiling = uint64(config.queues.cores)*3 # Validated 2..341 cores prove this profile multiplication fits.
  if uint32(target) <= uint32(previousTime): fail(ReadyReconciliationError.InvalidSlot)
  if slots > high(int) div sizeof(ReadyRow) or uint64(slots) > uint64(config.queues.maxBytes): fail(
      ReadyReconciliationError.LimitExceeded)
  var reports = 0
  var dependencies = 0
  if not charge(reports, old.value.items, config.reports, sizeof(ReadyItem)) or
      not charge(reports, available.len, config.reports, sizeof(ReadyItem)) or
      not charge(dependencies, old.value.dependencies, config.dependencies, sizeof(PackageHash)):
    fail(ReadyReconciliationError.LimitExceeded) # Inspect even expiring input rows under bounded report/dependency work.
  if uint64(processed.len) > uint64(config.processed) or processed.len > high(int) div sizeof(PackageHash):
    fail(ReadyReconciliationError.LimitExceeded) # Bound actual processed membership scratch independently.
  if uint64(accumulated.value.items) > uint64(config.historyHashes) or accumulated.value.items >
      high(int) div sizeof(PackageHash):
    fail(ReadyReconciliationError.LimitExceeded) # Original history union has its own fixed-hash ceiling.
  for slot in 0..<slots:
    let length = parent.readySlotCount(WorkQueueSlot(uint64(slot))).value
    if uint64(length) > uint64(config.queues.perSlot): fail(ReadyReconciliationError.LimitExceeded)
    for index in 0..<length:
      let item = parent.readyItemAt(WorkQueueSlot(uint64(slot)), ReadyItemIndex(uint64(index))).value
      let facts = item.report.ownedReportInfo.value
      if uint64(facts.core) >= uint64(config.queues.cores): fail(
          ReadyReconciliationError.InvalidInput)
      if uint64(facts.header.erasureShards) > shardCeiling:
        fail(ReadyReconciliationError.InvalidInput) # Recheck old owners captured under a broader roster domain.
      if uint64(facts.consumed) > uint64(config.queues.reportBytes) or uint64(item.dependencies) >
          uint64(config.queues.perDependencies):
        fail(ReadyReconciliationError.LimitExceeded) # Previously looser capture cannot bypass child/work policy.
  for report in available:
    let facts = report.ownedReportInfo
    if facts.error != OwnershipError.None: fail(ReadyReconciliationError.InvalidInput)
    if uint64(facts.value.core) >= uint64(config.queues.cores): fail(
        ReadyReconciliationError.InvalidInput)
    if uint64(facts.value.header.erasureShards) > shardCeiling: fail(
        ReadyReconciliationError.InvalidInput)
    if uint64(facts.value.consumed) > uint64(config.queues.reportBytes): fail(
        ReadyReconciliationError.LimitExceeded)
    # Both descriptor counts are report-codec bounded, so their sum fits native int before charging aggregate work.
    if not charge(dependencies, facts.value.prerequisiteCount+facts.value.lookupCount,
        config.dependencies, sizeof(PackageHash)):
      fail(ReadyReconciliationError.LimitExceeded)
  var done = @processed
  done.sort(compareHash)
  var past = newSeq[PackageHash](accumulated.value.items)
  var cursor = 0
  for slot in 0..<slots:
    for index in 0..<history.accumulatedSlotCount(WorkQueueSlot(uint64(slot))).value:
      past[cursor] = history.accumulatedHashAt(WorkQueueSlot(uint64(slot)), WorkQueueHashIndex(
          uint64(index))).value
      inc cursor # All parent history hashes, including the oldest row, belong to the original union.
  past.sort(compareHash)
  var deferred: ReadyRow = @[]
  for report in available:
    let facts = report.ownedReportInfo.value
    if facts.prerequisiteCount == 0 and facts.lookupCount ==
        0: continue # Immediate reports are never queued merely because they remain unprocessed.
    if past.contains(facts.header.packageHash) or done.contains(
        facts.header.packageHash): continue # D/E removes previously or newly processed identities.
    var hashes: seq[PackageHash] = @[]
    for index in 0..<facts.prerequisiteCount: hashes.add(report.ownedReportPrerequisite(index).value)
    for index in 0..<facts.lookupCount: hashes.add(report.ownedReportLookup(
        index).value.packageHash)
    hashes.sort(compareHash)
    var unique: seq[PackageHash] = @[]
    for hash in hashes:
      if unique.len == 0 or compareHash(unique[^1], hash) != 0:
        unique.add(hash) # D unions prerequisite and lookup identities before subtracting both satisfied sets.
    var remaining: seq[PackageHash] = @[]
    for hash in unique:
      if not past.contains(hash) and not done.contains(hash): remaining.add(hash)
    deferred.add(ReadyItem(report: report, dependencies: remaining)) # Preserve newly available report order, even when D/E empties its set.
  var rows = newSeq[ReadyRow](slots)
  let current = int(uint64(uint32(target)) mod uint64(slots))
  let elapsed = uint64(uint32(target))-uint64(uint32(previousTime))
  rows[current] = deferred
  var expired = 0
  for age in 1..<slots:
    if uint64(age) < elapsed:
      inc expired # Cleared intervening slots remain initialized empty rows, including gaps of an epoch or more.
      continue
    let position = if age <= current: current-age else: slots-(age-current)
    let length = parent.readySlotCount(WorkQueueSlot(uint64(position))).value
    for index in 0..<length:
      let item = parent.readyItemAt(WorkQueueSlot(uint64(position)), ReadyItemIndex(uint64(index))).value
      if done.contains(item.report.ownedReportInfo.value.header.packageHash): continue # Remove every matching processed report from surviving old rows.
      var hashes: seq[PackageHash] = @[]
      for dependency in 0..<item.dependencies:
        hashes.add(parent.readyDependencyAt(WorkQueueSlot(uint64(position)), ReadyItemIndex(uint64(
            index)), WorkQueueHashIndex(uint64(dependency))).value)
      rows[position].add(edited(item.report, hashes,
          done)) # Only newly processed membership edits parent dependencies.
  let encoded = readyStateEntry(rows, config.queues)
  if encoded.error != WorkQueueError.None:
    return ReadyReconciliationResult[ReadyReconciliationProjection](
        status: ReadyReconciliationError.CodecFailure, codecReason: encoded.error)
  let captured = decodeReadyState(encoded.value.value, config.queues)
  if captured.error != WorkQueueError.None:
    return ReadyReconciliationResult[ReadyReconciliationProjection](
        status: ReadyReconciliationError.CodecFailure, codecReason: captured.error)
  let info = captured.value.snapshot.readyInfo.value
  ReadyReconciliationResult[ReadyReconciliationProjection](status: ReadyReconciliationError.None,
    completed: ReadyReconciliationProjection(entry: encoded.value, queue: captured.value.snapshot,
      info: ReadyReconciliationInfo(available: available.len, processed: processed.len,
        expiredRows: expired,
        slots: slots, reports: info.items, dependencies: info.dependencies)))

proc readyReconciliationInfo*(plan: PreparedReadyReconciliation): ReadyReconciliationResult[
    ReadyReconciliationInfo] =
  ## Copy complete reconciliation observations.
  let data = plan.data
  if data == nil: return ReadyReconciliationResult[ReadyReconciliationInfo](
      status: ReadyReconciliationError.Uninitialized)
  ReadyReconciliationResult[ReadyReconciliationInfo](status: ReadyReconciliationError.None,
      completed: data.projection.info)
proc readyReconciliationSource*(plan: PreparedReadyReconciliation): ReadyReconciliationResult[
    PublishedAccumulation] =
  ## Retain the exact coordinated accumulation successor that supplies publication context.
  let data = plan.data
  if data == nil: return ReadyReconciliationResult[PublishedAccumulation](
      status: ReadyReconciliationError.Uninitialized)
  ReadyReconciliationResult[PublishedAccumulation](status: ReadyReconciliationError.None,
      completed: data.source)
proc readyReconciliationPrior*(plan: PreparedReadyReconciliation): ReadyReconciliationResult[
    StateStoreSnapshot] =
  ## Retain the complete coordinated stage prior required by mutable publication.
  let data = plan.data
  if data == nil: return ReadyReconciliationResult[StateStoreSnapshot](
      status: ReadyReconciliationError.Uninitialized)
  ReadyReconciliationResult[StateStoreSnapshot](status: ReadyReconciliationError.None,
      completed: data.prior)
proc readyReconciliationEntry*(plan: PreparedReadyReconciliation): ReadyReconciliationResult[StateEntry] =
  ## Copy fresh canonical C(14) bytes without exposing immutable retained storage.
  let data = plan.data
  if data == nil: return ReadyReconciliationResult[StateEntry](
      status: ReadyReconciliationError.Uninitialized)
  ReadyReconciliationResult[StateEntry](status: ReadyReconciliationError.None,
      completed: data.projection.entry)
proc readyReconciliationQueue*(plan: PreparedReadyReconciliation): ReadyReconciliationResult[
    ReadySnapshot] =
  ## Retain immutable ready rows for nominal codec accessors.
  let data = plan.data
  if data == nil: return ReadyReconciliationResult[ReadySnapshot](
      status: ReadyReconciliationError.Uninitialized)
  ReadyReconciliationResult[ReadySnapshot](status: ReadyReconciliationError.None,
      completed: data.projection.queue)
proc publishedReadySource*(plan: PublishedReadyReconciliation): ReadyReconciliationResult[
    PreparedReadyReconciliation] =
  ## Retain the exact queue preparation independently of caller lifetime.
  let data = plan.data
  if data == nil: return ReadyReconciliationResult[PreparedReadyReconciliation](
      status: ReadyReconciliationError.Uninitialized)
  ReadyReconciliationResult[PreparedReadyReconciliation](status: ReadyReconciliationError.None,
      completed: data.source)
proc publishedReadyState*(plan: PublishedReadyReconciliation): ReadyReconciliationResult[
    StateStoreSnapshot] =
  ## Retain the immutable complete successor; no partial light state or mutable store alias escapes.
  let data = plan.data
  if data == nil: return ReadyReconciliationResult[StateStoreSnapshot](
      status: ReadyReconciliationError.Uninitialized)
  ReadyReconciliationResult[StateStoreSnapshot](status: ReadyReconciliationError.None,
      completed: data.state)

proc prepareReadyReconciliation*(source: PublishedAccumulation,
    config: ReadyReconciliationConfig): ReadyReconciliationResult[PreparedReadyReconciliation] =
  ## Derive original rings/time/availability and processed prefix from one exact coordinated accumulation source.
  template fail(reason: ReadyReconciliationError) =
    ## Refuse without exposing a source prefix or partial projection.
    return ReadyReconciliationResult[PreparedReadyReconciliation](status: reason)
  let publication = source.publishedAccumulationSource
  if publication.error != AccumulationPublicationError.None: fail(
      ReadyReconciliationError.InvalidSource)
  let activity = publication.value.accumulationPublicationSource.value
  let finalized = activity.blockActivitySource.value.serviceActivitySource.value.statisticsSource.value
  let queue = finalized.finalAccumulationOutputs.value.outputsSource.value.executionRound.value.roundBlockQueue.value
  let stage = queue.accumulationAdmission.value.reportBlockStage.value
  let profile = stage.blockTransitionProfile
  if uint64(profile.cores) != uint64(config.queues.cores) or uint64(profile.epochSlots) != uint64(
      config.queues.epochSlots):
    fail(ReadyReconciliationError.InvalidConfig)
  let parent = stage.value.admitted.admittedState
  let ready = parent.lookup(chapterKey(StateChapter(14)))
  let history = parent.lookup(chapterKey(StateChapter(15)))
  let time = parent.lookup(chapterKey(StateChapter(11)))
  if ready.error != StateStoreError.None or history.error != StateStoreError.None or time.error !=
      StateStoreError.None:
    fail(ReadyReconciliationError.InvalidState)
  if uint64(ready.value.byteLength) > uint64(config.queues.maxBytes) or uint64(
      history.value.byteLength) > uint64(config.queues.maxBytes):
    fail(ReadyReconciliationError.LimitExceeded)
  let old = decodeReadyState(ready.value.bytes, config.queues)
  let past = decodeAccumulatedState(history.value.bytes, config.queues)
  for reason in [old.error, past.error]:
    if reason != WorkQueueError.None:
      return ReadyReconciliationResult[PreparedReadyReconciliation](
          status: ReadyReconciliationError.CodecFailure, codecReason: reason)
  let previous = decodeStateTime(time.value.bytes)
  if old.value.consumed != ready.value.byteLength or past.value.consumed !=
      history.value.byteLength:
    fail(ReadyReconciliationError.InvalidState) # Both original ring chapters require exact consumption.
  if previous.error != StateComponentError.None or previous.value.consumed != time.value.byteLength:
    fail(ReadyReconciliationError.InvalidState) # Parent time cannot be a valid prefix with trailing bytes.
  let count = stage.value.availability.availableReportCount
  let processed = uint64(finalized.finalAccumulationInfo.value.completedPrefix)
  if uint64(count) > uint64(config.reports) or count > high(int) div sizeof(OwnedReport): fail(
      ReadyReconciliationError.LimitExceeded)
  if processed > uint64(config.processed) or processed > uint64(high(int) div sizeof(
      PackageHash)): fail(ReadyReconciliationError.LimitExceeded)
  var available = newSeq[OwnedReport](count)
  for index in 0..<count: available[index] = stage.value.availability.availableReportAt(index).value
  var done = newSeq[PackageHash](int(processed))
  let selected = queue.accumulationProjection.value
  for index in 0..<done.len: done[index] = selected.accumulationAt(AccumulationIndex(uint64(
      index))).value.ownedReportInfo.value.header.packageHash
  let target = StateTime(uint32(stage.value.admitted.admittedHeader.headerInfo.value.unsigned.slot))
  let projected = projectReadyReconciliation(old.value.snapshot, past.value.snapshot, available,
      done, previous.value.value, target, config)
  if projected.error == ReadyReconciliationError.CodecFailure:
    return ReadyReconciliationResult[PreparedReadyReconciliation](
        status: ReadyReconciliationError.CodecFailure, codecReason: projected.codecError)
  if projected.error != ReadyReconciliationError.None: fail(projected.error)
  ReadyReconciliationResult[PreparedReadyReconciliation](status: ReadyReconciliationError.None,
    completed: PreparedReadyReconciliation(data: ReadyData(source: source,
        prior: source.publishedAccumulationState.value, projection: projected.value)))

proc commit(state: var StateStore, source: PreparedReadyReconciliation): ReadyReconciliationResult[
    PublishedReadyReconciliation] =
  ## Internal exact-prior publication applies at most one changed C(14) entry under inherited store limits.
  let data = source.data
  if data == nil: return ReadyReconciliationResult[PublishedReadyReconciliation](
      status: ReadyReconciliationError.InvalidSource)
  let current = state.snapshot
  if current.error != StateStoreError.None: return ReadyReconciliationResult[
      PublishedReadyReconciliation](status: ReadyReconciliationError.InvalidState)
  if not sameStateSnapshot(current.value, data.prior): return ReadyReconciliationResult[
      PublishedReadyReconciliation](status: ReadyReconciliationError.ForeignState)
  var working = forkStateStore(data.prior).value
  var writes: seq[StateWrite] = @[]
  let entry = data.projection.entry
  if data.prior.lookup(entry.key).value.bytes != entry.value:
    writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put,
        value: entry.value)) # Unchanged queues preserve identity without hashing.
  let applied = working.apply(writes)
  if applied.error != StateStoreError.None:
    return ReadyReconciliationResult[PublishedReadyReconciliation](
        status: ReadyReconciliationError.StateFailure, stateReason: applied.error)
  state = working # Sole mutable publication point after complete Merklization or a proved no-op.
  ReadyReconciliationResult[PublishedReadyReconciliation](status: ReadyReconciliationError.None,
    completed: PublishedReadyReconciliation(data: PublishedData(source: source,
        state: applied.value)))
proc publishReadyReconciliation*(source: PreparedReadyReconciliation): ReadyReconciliationResult[
    PublishedReadyReconciliation] =
  ## Create a private complete-map queue successor from the retained coordinated prior.
  let data = source.data
  if data == nil: return ReadyReconciliationResult[PublishedReadyReconciliation](
      status: ReadyReconciliationError.InvalidSource)
  var working = forkStateStore(data.prior).value
  commit(working, source)
proc advanceReadyReconciliation*(state: var StateStore,
    source: PreparedReadyReconciliation): ReadyReconciliationResult[PublishedReadyReconciliation] =
  ## Publish once only when the caller still owns the exact retained coordinated prior.
  commit(state, source)
