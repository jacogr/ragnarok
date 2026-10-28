# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_ready_arc_release"}

## Independent ready expiry/edit witnesses and genuine stopped-source private publication with ARC release evidence.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_ready as state_accumulation_ready
import ../../../src/state/accumulation_history as state_accumulation_history
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/state/accumulation_outputs as state_accumulation_outputs
import ../../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/owned as codec_owned
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/work_report as codec_work_report
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_outputs as codec_state_outputs
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../support/state_accumulation_reentry_context
import ../../support/state_accumulation_execution_context
import ../../support/pvm_accumulation_provision
import ../../support/state_report_context
import ../../support/testing_arc_evidence

# Disable backend hashing after real source construction; projection must remain entirely pure.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

# Small literal package identities make dependency and order expectations independent of report framing.
func key(value: byte): PackageHash =
  result = PackageHash(bytes: default(array[32, byte]))
  result.bytes[0] = value

# Bound all input work independently from the output codec policies.
proc policy(slots = 4'u64): AccumulationReadyConfig =
  AccumulationReadyConfig(items: ElementLimit(100), dependencies: ElementLimit(100),
    queues: WorkQueueConfig(epochSlots: EpochSlots(slots), cores: CoreCount(2),
      perSlot: ElementLimit(20), totalItems: ElementLimit(40), perDependencies: ElementLimit(20),
      totalDependencies: ElementLimit(100), reportBytes: ByteLimit(4096), maxBytes: ByteLimit(65536)))

## Capture a complete report with explicitly authored identity and canonical prerequisite/lookup fields.
proc report(base: OwnedReport, id: byte, deps: openArray[PackageHash] = [],
    lookups: openArray[SegmentLookup] = []): OwnedReport =
  let raw = reportBytes(base)
  var changed = decodeReportBorrowed(raw, 2).value
  changed.header.packageHash = key(id)
  changed.prerequisiteCount = deps.len
  changed.lookupCount = lookups.len
  for i in 0..<deps.len: changed.prerequisites[i] = deps[i] # Caller supplies sorted unique source sets.
  for i in 0..<lookups.len: changed.lookup[i] = lookups[i] # Preserve paired roots independently of keys.
  var output = newSeq[byte](raw.len+1024)
  let encoded = encodeReportBorrowed(changed, raw, 2, output)
  assert encoded.error == CompositeError.None
  decodeOwnedReport(output.toOpenArray(0, encoded.written-1), 2).value

# Actual source-derived guest execution supplies every completed round; idle entries have no guests.
proc completed(source: PreparedAccumulationReentry,
    provided = false): CompletedAccumulationReentry =
  var runs: seq[AccumulationDispatchResult] = @[]
  for index in 0..<source.reentryInputs.value.invocationServiceCount.value:
    runs.add(reentryGuest(source, uint64(index), provided = provided and index == 0))
  completeAccumulationReentry(source, runs, [], executionLimits()).value

# The fixed four-report fixture needs one dispatched reentry, followed by its genuine terminal entry.
proc finished(fixture: ReentryFixture, provided = false): PreparedFinalAccumulation =
  let limits = AccumulationOutputHistoryLimits(rounds: ElementLimit(4), executions: ElementLimit(6),
    log: OutputLogConfig(items: ElementLimit(0), maxBytes: ByteLimit(1)))
  if not fixture.source.reentryInfo.value.dispatch:
    return prepareFinalAccumulation(fixture.source.reentrySource.value,
        limits).value # Earliest genuine stopped certificate.
  let policy = executionRoundConfig()
  let next = AccumulationReentryConfig(selection: AccumulationContinuationLimits(
    executions: ElementLimit(2), reports: ElementLimit(4), digests: ElementLimit(8)),
    operands: policy.operands, inputs: policy.inputs)
  let terminal = prepareAccumulationReentry(completed(fixture.source, provided), next,
    AccumulationReentryDepthLimit(2)).value
  assert not terminal.reentryInfo.value.dispatch
  prepareFinalAccumulation(completed(terminal), limits).value

# Capture authored rings with a generous independent source policy before tightening projection bounds.
proc captured(rows: seq[ReadyRow]): ReadySnapshot =
  let cfg = policy(uint64(rows.len)).queues
  decodeReadyState(readyStateEntry(rows, cfg).value.value, cfg).value.snapshot

proc accumulated(rows: seq[AccumulatedRow]): AccumulatedSnapshot =
  ## Retain an independently authored history union.
  let cfg = policy(uint64(rows.len)).queues
  decodeAccumulatedState(accumulatedStateEntry(rows, cfg).value.value, cfg).value.snapshot

proc ids(ring: ReadySnapshot, slot: uint64, expected: openArray[byte]) =
  ## Compare ordered reports, preserving duplicates and their exact nominal package identities.
  let position = WorkQueueSlot(slot)
  assert ring.readySlotCount(position).value == expected.len
  for index in 0..<expected.len:
    assert ring.readyItemAt(position, ReadyItemIndex(uint64(
        index))).value.report.ownedReportInfo.value.header.packageHash.bytes == key(expected[index]).bytes

proc pureCases(base: OwnedReport) =
  ## One skipped slot clears age 1, preserves age 2/3, replaces age 0 and edits only the actual processed set.
  let cfg = policy()
  let a = report(base, 10)
  let b = report(base, 11)
  let c = report(base, 12)
  let d = report(base, 13)
  let parent = captured(@[@[ReadyItem(report: a, dependencies: @[key(1), key(2)])],
    @[ReadyItem(report: b)], @[ReadyItem(report: c)], @[ReadyItem(report: d)]])
  let old = accumulated(@[@[key(3)], @[], @[], @[]])
  var available = @[report(base, 20), report(base, 21, [key(1), key(3)],
    [SegmentLookup(packageHash: key(1), segmentRoot: default(SegmentRoot)),
     SegmentLookup(packageHash: key(4), segmentRoot: default(SegmentRoot))]),
    report(base, 3, [key(99)]), report(base, 22, [key(1)]), report(base, 23, [key(9)])]
  var processed = @[key(1), key(22), key(1)]
  failHash(3)
  var projected = projectAccumulationReady(parent, old, available, processed, HeaderSlot(0),
      HeaderSlot(2), cfg).value
  ids(projected.ring, 0, [10'u8])
  ids(projected.ring, 1, [])
  ids(projected.ring, 2, [21'u8, 23])
  ids(projected.ring, 3, [13'u8])
  assert projected.ring.readyItemAt(WorkQueueSlot(0), ReadyItemIndex(0)).value.dependencies == 1
  assert projected.ring.readyDependencyAt(WorkQueueSlot(0), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes == key(2).bytes
  assert projected.ring.readyItemAt(WorkQueueSlot(2), ReadyItemIndex(0)).value.dependencies == 1
  assert projected.ring.readyDependencyAt(WorkQueueSlot(2), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes == key(4).bytes
  # Literal framing uses unchanged complete report bytes and fixed dependency octets; no posterior encoder generates expectations.
  var expected: seq[byte] = @[1'u8]
  for octet in reportBytes(a): expected.add(octet)
  expected.add(1'u8)
  for octet in key(2).bytes: expected.add(octet)
  expected.add(0'u8)
  expected.add(2'u8)
  for item in [ReadyItem(report: available[1], dependencies: @[key(4)]),
      ReadyItem(report: available[4], dependencies: @[key(9)])]:
    for octet in reportBytes(item.report): expected.add(octet)
    expected.add(1'u8)
    for octet in item.dependencies[0].bytes: expected.add(octet)
  expected.add(1'u8)
  for octet in reportBytes(d): expected.add(octet)
  expected.add(0'u8)
  assert projected.entry.value == expected
  processed[0] = key(99)
  available[1] = default(OwnedReport)
  projected.entry.value[0] = 0
  ids(projected.ring, 0, [10'u8])
  ids(projected.ring, 2, [21'u8, 23])
  ids(parent, 1, [11'u8])
  # Ordinary advance, epoch wrap and an entire elapsed epoch have distinct literal retained rows.
  let one = projectAccumulationReady(parent, old, [], [], HeaderSlot(0), HeaderSlot(1),
      cfg).value.ring
  ids(one, 0, [10'u8]); ids(one, 1, []); ids(one, 2, [12'u8]); ids(one, 3, [13'u8])
  let wrap = projectAccumulationReady(parent, old, [], [key(12)], HeaderSlot(3), HeaderSlot(5),
      cfg).value.ring
  ids(wrap, 0, []); ids(wrap, 1, []); ids(wrap, 2, []); ids(wrap, 3, [13'u8])
  for slot in [4'u32, 5, high(uint32)]:
    assert projectAccumulationReady(parent, old, [], [], HeaderSlot(0), HeaderSlot(slot),
        cfg).value.entry.value == newSeq[byte](4)
  # New deferred rows remain even when unlocked; immediate reports never become posterior queued work.
  let deferred = projectAccumulationReady(parent, old, [report(base, 30, [key(3)]), report(base, 31)],
    [], HeaderSlot(0), HeaderSlot(4), cfg).value.ring
  ids(deferred, 0, [30'u8])
  assert deferred.readyItemAt(WorkQueueSlot(0), ReadyItemIndex(0)).value.dependencies == 0
  let singleton = captured(@[@[ReadyItem(report: a)]])
  assert projectAccumulationReady(singleton, accumulated(newSeq[AccumulatedRow](1)), [], [],
      HeaderSlot(3), HeaderSlot(4), policy(1)).value.entry.value == @[0'u8]
  for slot in [0'u32, 1]:
    assert projectAccumulationReady(parent, old, [], [], HeaderSlot(1), HeaderSlot(slot),
        cfg).error == AccumulationReadyError.InvalidTime
  assert projectAccumulationReady(default(ReadySnapshot), old, [], [], HeaderSlot(0), HeaderSlot(1),
      cfg).error == AccumulationReadyError.InvalidState
  assert projectAccumulationReady(parent, old, [default(OwnedReport)], [], HeaderSlot(0),
      HeaderSlot(1), cfg).error == AccumulationReadyError.InvalidReport
  assert projectAccumulationReady(parent, old, [], [], HeaderSlot(0), HeaderSlot(1), policy(
      3)).error == AccumulationReadyError.InvalidConfig
  for kind in 0..<5:
    var short = cfg
    case kind
    of 0: short.items = ElementLimit(4) # Four ready reports plus one history hash need five input units.
    of 1: short.dependencies = ElementLimit(1)
    of 2: short.queues.reportBytes = ByteLimit(1)
    of 3: short.queues.maxBytes = ByteLimit(3)
    else: short.queues.perDependencies = ElementLimit(1)
    assert projectAccumulationReady(parent, old, [], [], HeaderSlot(0), HeaderSlot(4),
        short).error == AccumulationReadyError.LimitExceeded
  var exact = cfg
  exact.items = ElementLimit(5)
  exact.dependencies = ElementLimit(2)
  assert projectAccumulationReady(parent, old, [], [], HeaderSlot(0), HeaderSlot(4),
      exact).value.entry.value == newSeq[byte](4)
  var full = cfg
  full.items = ElementLimit(high(uint64))
  full.dependencies = ElementLimit(high(uint64))
  assert projectAccumulationReady(parent, old, [], [], HeaderSlot(0), HeaderSlot(4),
      full).value.entry.value == newSeq[byte](4)
  var shortOutput = cfg
  shortOutput.queues.perSlot = ElementLimit(1)
  let refused = projectAccumulationReady(parent, old,
    [report(base, 21, [key(1)]), report(base, 23, [key(1)])], [], HeaderSlot(0), HeaderSlot(4), shortOutput)
  assert refused.codecError == WorkQueueError.LimitExceeded
  failHash(0)

proc main() {.raises.} =
  ## Genuine signed finalized candidates test full/partial/empty execution and unchanged complete predecessor maps.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  pureCases(base)
  let cfg = policy(12)
  let historyConfig = AccumulationHistoryConfig(reports: ElementLimit(4), queues: cfg.queues)
  let fixture = reentryFixture(base)
  let history = prepareAccumulationHistory(finished(fixture), historyConfig).value
  let prior = history.accumulationHistoryState.value
  let readyKey = chapterKey(StateChapter(14))
  let originalReady = prior.lookup(readyKey).value.bytes
  failHash(1)
  let refused = prepareAccumulationReady(history, cfg)
  assert refused.error == AccumulationReadyError.StateFailure
  assert refused.stateError == StateStoreError.BackendFailure
  assert prior.lookup(readyKey).value.bytes == originalReady
  failHash(0)
  let plan = prepareAccumulationReady(history, cfg).value
  let candidate = plan.accumulationReadyState.value
  assert candidate.lookup(readyKey).value.bytes == newSeq[byte](12)
  assert plan.accumulationReadyEntry.value.value == newSeq[byte](12)
  assert sameStateSnapshot(plan.accumulationReadySource.value.accumulationHistoryState.value, prior)
  var expected: seq[StateEntry] = @[]
  for entry in fixture.initial.entries:
    let chapter = array[31, byte](entry.key)
    let bytes = if chapter == array[31, byte](readyKey): newSeq[byte](12)
      elif chapter == array[31, byte](chapterKey(StateChapter(15))): prior.lookup(
          entry.key).value.bytes
      else: entry.value
    expected.add(StateEntry(key: entry.key, value: bytes))
    if chapter != array[31, byte](readyKey): assert candidate.lookup(entry.key).value.bytes ==
        prior.lookup(entry.key).value.bytes
  expected.add(StateEntry(key: chapterKey(StateChapter(16)), value: @[0'u8]))
  let expectedState = newStateStore(expected, state_report_context.limits()).value.snapshot.value
  assert array[32, byte](expectedState.commitment.root) == array[32, byte](
      candidate.commitment.root)
  var entry = plan.accumulationReadyEntry.value
  entry.value[0] = 9
  assert plan.accumulationReadyEntry.value.value == newSeq[byte](12)
  for fixture in [reentryFixture(base, stopped = true), reentryFixture(base, empty = true)]:
    let source = prepareAccumulationHistory(finished(fixture), historyConfig).value
    let partial = prepareAccumulationReady(source, cfg).value
    let processed = uint64(source.accumulationHistorySource.value.finalAccumulationInfo.value.completedPrefix)
    assert partial.accumulationReadyRing.value.readyInfo.value.items == (if processed == 0: 0 else: 3)
    if processed > 0:
      # The signed parent puts reports in row 0; age 2 at candidate 2 retains the unaffordable suffix.
      let ring = partial.accumulationReadyRing.value
      for index in 0..<3:
        assert ring.readyItemAt(WorkQueueSlot(0), ReadyItemIndex(uint64(
            index))).value.report.ownedReportInfo.value.header.packageHash.bytes[0] == byte(65+index)
  let provided = prepareAccumulationHistory(finished(reentryFixture(base, provided = true),
      provided = true), historyConfig).value
  let providedPlan = prepareAccumulationReady(provided, cfg).value
  let request = provisionRequest(42, @[73'u8])
  assert providedPlan.accumulationReadyState.value.lookup(request.key).value.bytes == @[1'u8, 2, 0, 0, 0]
  let empty = default(PreparedAccumulationReady)
  assert empty.accumulationReadySource.error == AccumulationReadyError.Uninitialized
  assert empty.accumulationReadyRing.error == AccumulationReadyError.Uninitialized
  assert empty.accumulationReadyState.error == AccumulationReadyError.Uninitialized
  assert empty.accumulationReadyEntry.error == AccumulationReadyError.Uninitialized
  assert prepareAccumulationReady(default(PreparedAccumulationHistory), cfg).error ==
      AccumulationReadyError.InvalidSource
  assert prepareAccumulationReady(history, policy(11)).error == AccumulationReadyError.InvalidConfig
  var wrongCore = cfg
  wrongCore.queues.cores = CoreCount(3)
  assert prepareAccumulationReady(history, wrongCore).error == AccumulationReadyError.InvalidConfig
  var short = cfg
  short.queues.maxBytes = ByteLimit(11)
  assert prepareAccumulationReady(history, short).error == AccumulationReadyError.LimitExceeded
  short = cfg
  short.items = ElementLimit(3)
  assert prepareAccumulationReady(history, short).error == AccumulationReadyError.LimitExceeded
  var detached: PreparedAccumulationReady
  block:
    let local = prepareAccumulationHistory(finished(reentryFixture(base)), historyConfig).value
    detached = prepareAccumulationReady(local, cfg).value
  assert detached.accumulationReadyEntry.value.value == newSeq[byte](12)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    failHash(1)
    assert prepareAccumulationReady(history, cfg).stateError == StateStoreError.BackendFailure
    failHash(0)
    let current = prepareAccumulationReady(history, cfg).value
    assert array[32, byte](current.accumulationReadyState.value.commitment.root) == array[32, byte](
        candidate.commitment.root)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_ready", 1000, before, after)
  echo "Accumulation ready queue passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # I/O and unexpected errors remain strict native failures.
except:
  quit(2)
