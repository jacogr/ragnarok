# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal ready-ring framing and source-bound full-map witnesses distinguish newly deferred work from planner q.

import std/assertions
import ../../src/state/[ready_reconciliation, accumulation_publication, store]
import ../../src/codec/[bounded, composite, owned, report_owned, work_report, state_safrole,
  state_workqueues, state_layout, state_trie]
import ./report_context

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc readyPolicy*(slots = 12'u64): ReadyReconciliationConfig =
  ## Inspected work and complete output framing have separate finite ceilings.
  ReadyReconciliationConfig(reports: ElementLimit(20), dependencies: ElementLimit(40),
    historyHashes: ElementLimit(10), processed: ElementLimit(10), queues: WorkQueueConfig(
      epochSlots: EpochSlots(slots), cores: CoreCount(2), perSlot: ElementLimit(10),
          totalItems: ElementLimit(20),
      perDependencies: ElementLimit(16), totalDependencies: ElementLimit(40),
          reportBytes: ByteLimit(2048), maxBytes: ByteLimit(20000)))
func key(id: byte): PackageHash =
  ## Literal full fixed hash identity separates package membership from roots and ordinals.
  result = PackageHash(bytes: default(array[32, byte]))
  result.bytes[0] = id
proc authoredReport(base: OwnedReport, id: byte, prerequisites: openArray[byte] = [],
    lookups: openArray[byte] = [], core = 0, shards = 6): OwnedReport =
  ## Capture an independently authored report with sorted prerequisite/lookup keys and a distinct non-key lookup root.
  let raw = reportBytes(base)
  var report = decodeReportBorrowed(raw, 341).value
  report.core = CoreIndex(core)
  report.header.packageHash = key(id)
  report.header.erasureShards = ErasureShards(shards)
  report.prerequisiteCount = prerequisites.len
  for index, id in prerequisites: report.prerequisites[index] = key(id)
  report.lookupCount = lookups.len
  for index, id in lookups: report.lookup[index] = SegmentLookup(packageHash: key(id),
      segmentRoot: SegmentRoot(bytes: key(240).bytes))
  var bytes = newSeq[byte](raw.len+1024)
  let encoded = encodeReportBorrowed(report, raw, 341, bytes)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(bytes.toOpenArray(0, encoded.written-1), 341).value
proc parent(rows: seq[ReadyRow], policy: ReadyReconciliationConfig): ReadySnapshot =
  ## Only input capture uses the existing codec; expected output framing is emitted literally.
  let entry = readyStateEntry(rows, policy.queues).value
  decodeReadyState(entry.value, policy.queues).value.snapshot
proc history(rows: seq[AccumulatedRow], policy: ReadyReconciliationConfig): AccumulatedSnapshot =
  ## Capture original accumulated membership independently of reconciliation.
  let entry = accumulatedStateEntry(rows, policy.queues).value
  decodeAccumulatedState(entry.value, policy.queues).value.snapshot
proc appendRow(bytes: var seq[byte], row: ReadyRow) =
  ## All authored counts fit one natural octet; copy report bytes and fixed dependency hashes without the ready encoder.
  assert row.len < 128
  bytes.add(byte(row.len))
  for item in row:
    for octet in reportBytes(item.report): bytes.add(octet)
    assert item.dependencies.len < 128
    bytes.add(byte(item.dependencies.len))
    for hash in item.dependencies:
      for octet in hash.bytes: bytes.add(octet)

proc checkReadyProjection*(base: OwnedReport) =
  ## Newly deferred D/E, immediate exclusion, old-history distinction, elapsed expiry and modulo wrap have literal expected rows.
  let policy = readyPolicy(4)
  let a = authoredReport(base, 10)
  let b = authoredReport(base, 11)
  let c = authoredReport(base, 12)
  let d = authoredReport(base, 13)
  let removed = authoredReport(base, 21)
  let n0 = authoredReport(base, 30, [2'u8, 9], [9'u8, 11])
  let n1 = authoredReport(base, 31, [9'u8])
  let immediate = authoredReport(base, 32)
  let pending = authoredReport(base, 33, [32'u8])
  let historic = authoredReport(base, 34, [5'u8])
  let processedReport = authoredReport(base, 35, [1'u8])
  let wrongCore = authoredReport(base, 50, core = 2)
  let wrongShards = authoredReport(base, 51, shards = 9)
  var broader = policy
  broader.queues.cores = CoreCount(3)
  let broaderParent = parent(@[@[ReadyItem(report: wrongShards)], @[], @[], @[]], broader)
  let available = [n0, n1, immediate, pending, historic, processedReport]
  let processed = [key(2), key(21), key(35), key(2)]
  let rows = @[@[ReadyItem(report: a, dependencies: @[key(1), key(2)])],
    @[ReadyItem(report: b, dependencies: @[key(3)])], @[ReadyItem(report: c)],
    @[ReadyItem(report: d, dependencies: @[key(2), key(9)]), ReadyItem(report: removed)]]
  let original = parent(rows, policy)
  let accumulated = history(@[@[key(9), key(34)], @[], @[], @[key(9)]], policy)
  var expected: seq[byte] = @[0'u8, 0]
  appendRow(expected, @[ReadyItem(report: n0, dependencies: @[key(11)]), ReadyItem(report: n1),
    ReadyItem(report: pending, dependencies: @[key(32)])])
  appendRow(expected, @[ReadyItem(report: d, dependencies: @[key(9)])])
  failHash(3)
  let result = projectReadyReconciliation(original, accumulated, available, processed, StateTime(3),
      StateTime(6), policy).value
  assert result.entry.value == expected
  assert result.info.reports == 4 and result.info.dependencies == 3 and result.info.expiredRows == 2
  assert result.info.available == 6 and result.info.processed == 4
  var copied = result.entry
  copied.value[0] = 99
  assert result.queue.readySlotCount(WorkQueueSlot(0)).value == 0
  assert result.queue.readyDependencyAt(WorkQueueSlot(3), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes == key(9).bytes
  var exact = policy
  exact.reports = ElementLimit(11)
  exact.dependencies = ElementLimit(13)
  exact.historyHashes = ElementLimit(3)
  exact.processed = ElementLimit(4)
  exact.queues.maxBytes = ByteLimit(uint64(expected.len))
  assert projectReadyReconciliation(original, accumulated, available, processed, StateTime(3),
      StateTime(6), exact).error == ReadyReconciliationError.None
  for mode in 0..<6:
    var short = exact
    case mode
    of 0: short.reports = ElementLimit(10) # Include all old rows even when they expire.
    of 1: short.dependencies = ElementLimit(12) # D work counts the prerequisite/lookup overlap before set union.
    of 2: short.historyHashes = ElementLimit(2) # Cross-row historical duplicates still consume inspected storage.
    of 3: short.processed = ElementLimit(3) # Repeated processed hashes consume input work despite set membership semantics.
    of 4: short.queues.reportBytes = ByteLimit(0) # Every inspected child owner is bounded.
    else: short.queues.perSlot = ElementLimit(1) # Revalidate old rows captured under looser policy.
    assert projectReadyReconciliation(original, accumulated, available, processed, StateTime(3),
        StateTime(6), short).error == ReadyReconciliationError.LimitExceeded
  var short = exact
  short.queues.maxBytes = ByteLimit(uint64(expected.len-1))
  let refusal = projectReadyReconciliation(original, accumulated, available, processed, StateTime(
      3), StateTime(6), short)
  assert refusal.error == ReadyReconciliationError.CodecFailure and refusal.codecError ==
      WorkQueueError.LimitExceeded
  var wide = exact
  wide.reports = ElementLimit(high(uint64))
  wide.dependencies = ElementLimit(high(uint64))
  wide.historyHashes = ElementLimit(high(uint64))
  wide.processed = ElementLimit(high(uint64))
  wide.queues.maxBytes = ByteLimit(high(uint64))
  assert projectReadyReconciliation(original, accumulated, available, processed, StateTime(3),
      StateTime(6), wide).value.entry.value == expected
  assert projectReadyReconciliation(original, accumulated, [default(OwnedReport)], [], StateTime(3),
      StateTime(6), policy).error == ReadyReconciliationError.InvalidInput
  assert projectReadyReconciliation(original, accumulated, [wrongCore], [], StateTime(3), StateTime(
      6), policy).error == ReadyReconciliationError.InvalidInput
  assert projectReadyReconciliation(original, accumulated, [wrongShards], [], StateTime(3),
      StateTime(6), policy).error == ReadyReconciliationError.InvalidInput
  assert projectReadyReconciliation(broaderParent, accumulated, [], [], StateTime(3), StateTime(6),
      policy).error == ReadyReconciliationError.InvalidInput
  assert projectReadyReconciliation(default(ReadySnapshot), accumulated, [], [], StateTime(3),
      StateTime(6), policy).error == ReadyReconciliationError.InvalidInput
  assert projectReadyReconciliation(original, default(AccumulatedSnapshot), [], [], StateTime(3),
      StateTime(6), policy).error == ReadyReconciliationError.InvalidInput
  for target in [2'u32, 3]:
    assert projectReadyReconciliation(original, accumulated, [], [], StateTime(3), StateTime(
        target), policy).error == ReadyReconciliationError.InvalidSlot
  var invalid = policy
  invalid.queues.epochSlots = EpochSlots(0)
  assert projectReadyReconciliation(original, accumulated, [], [], StateTime(3), StateTime(6),
      invalid).error == ReadyReconciliationError.InvalidConfig
  failHash(0)
  let simple = parent(@[@[ReadyItem(report: a)], @[ReadyItem(report: b)], @[ReadyItem(report: c)],
      @[ReadyItem(report: d)]], policy)
  let noHistory = history(newSeq[AccumulatedRow](4), policy)
  failHash(3)
  for index, target in [4'u32, 5, 6, 7, 8, high(uint32)]:
    let mask = [14, 12, 8, 0, 0, 0][index]
    let queue = projectReadyReconciliation(simple, noHistory, [], [], StateTime(3), StateTime(
        target), policy).value.queue
    for slot in 0..<4:
      assert queue.readySlotCount(WorkQueueSlot(uint64(slot))).value == (if (mask and (
          1 shl slot)) != 0: 1 else: 0)
  assert hashCalls() == 0
  failHash(0)
  let singletonPolicy = readyPolicy(1)
  let singleton = parent(@[@[ReadyItem(report: a)]], singletonPolicy)
  let singletonHistory = history(newSeq[AccumulatedRow](1), singletonPolicy)
  let replaced = projectReadyReconciliation(singleton, singletonHistory, [n0], [], StateTime(1),
      StateTime(2), singletonPolicy).value
  assert replaced.queue.readySlotCount(WorkQueueSlot(0)).value == 1
  assert replaced.queue.readyItemAt(WorkQueueSlot(0), ReadyItemIndex(0)).value.dependencies == 3

proc checkReadySource*(source: PublishedAccumulation, original: openArray[StateEntry],
    pending = false): PublishedReadyReconciliation =
  ## Completed and unaffordable source prefixes reconcile original slots over already coordinated statistics/history/accounts.
  let prior = source.publishedAccumulationState.value
  let readyKey = chapterKey(StateChapter(14))
  let policy = readyPolicy()
  let old = decodeReadyState(prior.lookup(readyKey).value.bytes, policy.queues).value.snapshot
  var expected: seq[byte] = @[]
  if pending:
    expected.add(3'u8)
    for index in 1..<4:
      let report = old.readyItemAt(WorkQueueSlot(0), ReadyItemIndex(uint64(index))).value.report
      assert report.ownedReportInfo.value.header.packageHash.bytes[0] == byte(64+index)
      for octet in reportBytes(report): expected.add(octet)
      expected.add(0'u8) # Unaffordable original suffix remains at slot zero, never copied into current slot two.
    for slot in 1..<12: expected.add(0'u8)
  else:
    expected = newSeq[byte](12) # Full/inactive processed cases have no surviving deferred ready records.
  failHash(3)
  let plan = prepareReadyReconciliation(source, policy).value
  assert plan.readyReconciliationEntry.value.value == expected
  assert plan.readyReconciliationInfo.value.reports == (if pending: 3 else: 0)
  assert plan.readyReconciliationInfo.value.available == 0
  assert plan.readyReconciliationQueue.value.readySlotCount(WorkQueueSlot(2)).value == 0
  assert sameStateSnapshot(plan.readyReconciliationPrior.value, prior)
  var bytes = plan.readyReconciliationEntry.value
  bytes.value[0] = 99
  assert plan.readyReconciliationEntry.value.value == expected
  var observed = plan.readyReconciliationInfo.value
  observed.reports = 999
  assert plan.readyReconciliationInfo.value.reports == (if pending: 3 else: 0)
  var short = policy
  short.queues.maxBytes = ByteLimit(0)
  assert prepareReadyReconciliation(source, short).error == ReadyReconciliationError.LimitExceeded
  short = policy
  short.queues.epochSlots = EpochSlots(11)
  assert prepareReadyReconciliation(source, short).error == ReadyReconciliationError.InvalidConfig
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareReadyReconciliation(source, policy).value
    assert local.readyReconciliationInfo.value.reports == (if pending: 3 else: 0)
  assert before == getOccupiedMem()
  assert hashCalls() == 0
  let unchanged = prior.lookup(readyKey).value.bytes == expected
  if unchanged:
    let published = publishReadyReconciliation(plan).value
    assert sameStateSnapshot(published.publishedReadyState.value, prior) and hashCalls() ==
        0 # Exact no-op needs no backend.
  failHash(0)
  var entries: seq[StateEntry] = @[]
  for record in original: entries.add(StateEntry(key: record.key, value: prior.lookup(
      record.key).value.bytes))
  let log = chapterKey(StateChapter(16))
  entries.add(StateEntry(key: log, value: prior.lookup(log).value.bytes))
  assert entries.len == prior.commitment.entries
  var foreign = newStateStore(entries, report_context.limits()).value
  failHash(3)
  assert advanceReadyReconciliation(foreign, plan).error == ReadyReconciliationError.ForeignState
  assert hashCalls() == 0
  failHash(0)
  if not unchanged:
    for successful in [0, 2]:
      var caller = forkStateStore(prior).value
      hashAfter(cint(successful))
      let refused = advanceReadyReconciliation(caller, plan)
      assert refused.error == ReadyReconciliationError.StateFailure and refused.stateError ==
          StateStoreError.BackendFailure
      failHash(0)
      assert sameStateSnapshot(caller.snapshot.value, prior)
  for index in 0..<entries.len:
    if array[31, byte](entries[index].key) == array[31, byte](readyKey): entries[
        index].value = expected
  let root = stateTrieRoot(entries, report_context.limits().trie).value
  let published = publishReadyReconciliation(plan).value
  let posterior = published.publishedReadyState.value
  assert array[32, byte](posterior.commitment.root) == array[32, byte](root.root)
  for record in entries: assert posterior.lookup(record.key).value.bytes ==
      record.value # Accounts/C(13)/C(15)/C(16) remain the coordinated values.
  var caller = forkStateStore(prior).value
  let advanced = advanceReadyReconciliation(caller, plan).value
  assert sameStateSnapshot(caller.snapshot.value, advanced.publishedReadyState.value)
  if not unchanged:
    let after = caller.snapshot.value
    failHash(3)
    assert advanceReadyReconciliation(caller, plan).error == ReadyReconciliationError.ForeignState
    assert sameStateSnapshot(caller.snapshot.value, after) and hashCalls() == 0
    failHash(0)
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = publishReadyReconciliation(plan).value
    assert local.publishedReadyState.value.lookup(readyKey).value.bytes == expected
  assert occupied == getOccupiedMem()
  assert sameStateSnapshot(source.publishedAccumulationState.value, prior)
  assert prepareReadyReconciliation(default(PublishedAccumulation), policy).error ==
      ReadyReconciliationError.InvalidSource
  assert publishReadyReconciliation(default(PreparedReadyReconciliation)).error ==
      ReadyReconciliationError.InvalidSource
  published
