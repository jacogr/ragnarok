# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_history_arc_release"}

## Literal ring shifts and genuine finalized prefixes advance only C(15), retaining immutable full-state provenance.

import std/[assertions, envvars, syncio]
import ../../../src/state/[accumulation_history, accumulation_finalization, accumulation_outputs,
  accumulation_reentry, accumulation_continuation, accumulation_execution, accumulation_inputs,
  accumulation_dispatch, store]
import ../../../src/codec/[bounded, composite, owned, report_owned, work_report,
  state_workqueues, state_outputs, state_layout, state_trie]
import ../../support/[accumulation_reentry_context, accumulation_execution_context,
  pvm_accumulation_provision, report_context, arc_evidence]

# Disable hashes after genuine source construction to distinguish pure projection from private map publication.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Fixed independent identity expectations make all ring ordering and duplicate behavior visible.
proc hash(id: byte): PackageHash =
  result = PackageHash(bytes: default(array[32, byte]))
  result.bytes[0] = id

# Accumulated history has no nested report/dependency payloads, so only its own codec fields need nonzero caps.
proc config(slots = 3'u64, reports = 4'u64, perSlot = 2'u64,
    items = 5'u64, bytes = 163'u64): AccumulationHistoryConfig =
  AccumulationHistoryConfig(reports: ElementLimit(reports), queues: WorkQueueConfig(
    epochSlots: EpochSlots(slots), cores: CoreCount(2), perSlot: ElementLimit(perSlot),
    totalItems: ElementLimit(items), maxBytes: ByteLimit(bytes)))

# Use the established codec only to capture authored inputs, never to generate expected shifted bytes.
proc captured(rows: seq[AccumulatedRow], config: AccumulationHistoryConfig): AccumulatedSnapshot =
  let entry = accumulatedStateEntry(rows, config.queues).value
  decodeAccumulatedState(entry.value, config.queues).value.snapshot

# Literal row count and full fixed hash bytes are independent of production C(15) encoding.
proc appendRow(bytes: var seq[byte], hashes: openArray[PackageHash]) =
  assert hashes.len < 128
  bytes.add(byte(hashes.len))
  for hash in hashes:
    for octet in hash.bytes: bytes.add(octet)

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

proc main() {.raises.} =
  let cfg = config()
  let parent = captured(@[@[hash(1)], @[hash(2), hash(3)], @[hash(3)]], cfg)
  var packages = @[hash(9), hash(8), hash(9), hash(8)]
  var expected: seq[byte] = @[]
  appendRow(expected, [hash(2), hash(3)])
  appendRow(expected, [hash(3)])
  appendRow(expected, [hash(8), hash(9)])
  failHash(3)
  var projected = projectAccumulationHistory(parent, packages, cfg).value
  assert projected.entry.value == expected
  assert projected.ring.accumulatedInfo.value.items == 5
  assert projected.ring.accumulatedSlotCount(WorkQueueSlot(2)).value == 2
  assert projected.ring.accumulatedHashAt(WorkQueueSlot(0), WorkQueueHashIndex(1)).value.bytes ==
      hash(3).bytes
  assert projected.ring.accumulatedHashAt(WorkQueueSlot(1), WorkQueueHashIndex(0)).value.bytes ==
      hash(3).bytes
  packages[0] = hash(77)
  projected.entry.value[0] = 99
  assert projected.ring.accumulatedSlotCount(WorkQueueSlot(0)).value == 2
  assert projected.ring.accumulatedHashAt(WorkQueueSlot(2), WorkQueueHashIndex(1)).value.bytes ==
      hash(9).bytes
  assert parent.accumulatedHashAt(WorkQueueSlot(0), WorkQueueHashIndex(0)).value.bytes == hash(1).bytes
  assert projectAccumulationHistory(parent, [], config(
      reports = 0)).value.ring.accumulatedInfo.value.items == 3
  let singletonConfig = config(slots = 1, reports = 0, perSlot = 1, items = 1, bytes = 33)
  let singleton = captured(@[@[hash(9)]], singletonConfig)
  assert projectAccumulationHistory(singleton, [], singletonConfig).value.entry.value == @[0'u8]
  for limit in [config(reports = 3), config(perSlot = 1), config(items = 3), config(bytes = 2)]:
    assert projectAccumulationHistory(parent, [hash(9), hash(8), hash(9), hash(8)], limit).error ==
        AccumulationHistoryError.LimitExceeded
  for limit in [config(bytes = 162), config(items = 4)]:
    let refused = projectAccumulationHistory(parent, [hash(9), hash(8)], limit)
    assert refused.error == AccumulationHistoryError.CodecFailure
    assert refused.codecError == WorkQueueError.LimitExceeded
  assert projectAccumulationHistory(parent, [hash(8), hash(9), hash(10)], cfg).codecError ==
      WorkQueueError.LimitExceeded
  assert projectAccumulationHistory(parent, [], config(slots = 4)).error ==
      AccumulationHistoryError.InvalidConfig
  var bad = cfg
  bad.queues.cores = CoreCount(1)
  assert projectAccumulationHistory(parent, [], bad).error == AccumulationHistoryError.InvalidConfig
  assert projectAccumulationHistory(default(AccumulatedSnapshot), [], cfg).error ==
      AccumulationHistoryError.InvalidState
  let wide = config(reports = high(uint64), perSlot = high(uint64), items = high(uint64),
      bytes = high(uint64))
  assert projectAccumulationHistory(parent, [hash(9), hash(8)], wide).value.entry.value == expected
  assert hashCalls() == 0
  failHash(0)
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let fixture = reentryFixture(base)
  let source = finished(fixture)
  let key = chapterKey(StateChapter(15))
  let prior = source.finalAccumulationState.value
  let oldBytes = newSeq[byte](12)
  assert prior.lookup(key).value.bytes == oldBytes
  var expectedBound = newSeq[byte](11)
  var hashes: seq[PackageHash] = @[]
  for id in [64'u8, 65, 66, 67]:
    var package = base.ownedReportInfo.value.header.packageHash
    package.bytes[0] = id
    hashes.add(package) # Authored fixture changes only the first identity octet before signing.
  appendRow(expectedBound, hashes)
  let boundConfig = config(slots = 12, perSlot = 4, items = 4, bytes = 140)
  failHash(3)
  let refused = prepareAccumulationHistory(source, boundConfig)
  assert refused.error == AccumulationHistoryError.StateFailure
  assert refused.stateError == StateStoreError.BackendFailure
  assert sameStateSnapshot(prior, source.finalAccumulationState.value)
  assert prior.lookup(key).value.bytes == oldBytes
  assert prepareAccumulationHistory(source, config(slots = 11)).error ==
      AccumulationHistoryError.InvalidConfig
  var wrongCore = boundConfig
  wrongCore.queues.cores = CoreCount(3)
  assert prepareAccumulationHistory(source, wrongCore).error ==
      AccumulationHistoryError.InvalidConfig
  assert prepareAccumulationHistory(source, config(slots = 12, reports = 3)).error ==
      AccumulationHistoryError.LimitExceeded
  assert prepareAccumulationHistory(source, config(slots = 12, bytes = 11)).error ==
      AccumulationHistoryError.LimitExceeded
  let shortWire = prepareAccumulationHistory(source, config(slots = 12, perSlot = 4, items = 4, bytes = 139))
  assert shortWire.codecError == WorkQueueError.LimitExceeded
  failHash(0)
  let plan = prepareAccumulationHistory(source, boundConfig).value
  let info = plan.accumulationHistoryInfo.value
  assert info.processedReports == 4 and info.newPackages == 4
  assert info.slots == 12 and info.packages == 4
  assert plan.accumulationHistoryEntry.value.value == expectedBound
  let candidate = plan.accumulationHistoryState.value
  assert candidate.lookup(key).value.bytes == expectedBound
  assert candidate.lookup(chapterKey(StateChapter(16))).value.bytes == @[0'u8]
  assert sameStateSnapshot(plan.accumulationHistorySource.value.finalAccumulationState.value, prior)
  var rows: seq[StateEntry] = @[]
  for entry in fixture.initial.entries:
    let value = if array[31, byte](entry.key) == array[31, byte](
        key): expectedBound else: entry.value
    rows.add(StateEntry(key: entry.key, value: value)) # Independent expected complete mapping changes only C(15)/earlier C(16).
    if array[31, byte](entry.key) != array[31, byte](key):
      assert candidate.lookup(entry.key).value.bytes == entry.value
  rows.add(StateEntry(key: chapterKey(StateChapter(16)), value: @[0'u8]))
  let expectedState = newStateStore(rows, report_context.limits()).value.snapshot.value
  assert array[32, byte](candidate.commitment.root) == array[32, byte](
      expectedState.commitment.root)
  var entry = plan.accumulationHistoryEntry.value
  entry.value[0] = 9
  assert plan.accumulationHistoryEntry.value.value == expectedBound
  var observed = plan.accumulationHistoryInfo.value
  observed.newPackages = high(int)
  assert plan.accumulationHistoryInfo.value.newPackages == 4
  for fixture in [reentryFixture(base, stopped = true), reentryFixture(base, empty = true)]:
    let source = finished(fixture)
    let plan = prepareAccumulationHistory(source, config(slots = 12, perSlot = 4, items = 4,
        bytes = 140)).value
    let processed = uint64(source.finalAccumulationInfo.value.completedPrefix)
    assert uint64(plan.accumulationHistoryInfo.value.processedReports) == processed
    assert uint64(plan.accumulationHistoryInfo.value.newPackages) == processed
    assert plan.accumulationHistoryRing.value.accumulatedSlotCount(WorkQueueSlot(11)).value == int(processed)
  let provided = finished(reentryFixture(base, provided = true), provided = true)
  let providedPlan = prepareAccumulationHistory(provided, boundConfig).value
  let request = provisionRequest(42, @[73'u8])
  assert providedPlan.accumulationHistoryState.value.lookup(request.key).value.bytes == @[1'u8, 2,
      0, 0, 0]
  assert sameStateSnapshot(providedPlan.accumulationHistorySource.value.finalAccumulationState.value,
      provided.finalAccumulationState.value)
  let empty = default(PreparedAccumulationHistory)
  assert empty.accumulationHistoryInfo.error == AccumulationHistoryError.Uninitialized
  assert empty.accumulationHistorySource.error == AccumulationHistoryError.Uninitialized
  assert empty.accumulationHistoryRing.error == AccumulationHistoryError.Uninitialized
  assert empty.accumulationHistoryState.error == AccumulationHistoryError.Uninitialized
  assert empty.accumulationHistoryEntry.error == AccumulationHistoryError.Uninitialized
  assert prepareAccumulationHistory(default(PreparedFinalAccumulation), boundConfig).error ==
      AccumulationHistoryError.InvalidSource
  var detached: PreparedAccumulationHistory
  block:
    let local = finished(reentryFixture(base))
    detached = prepareAccumulationHistory(local, boundConfig).value
  assert detached.accumulationHistoryEntry.value.value == expectedBound
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    failHash(1)
    assert prepareAccumulationHistory(source, boundConfig).stateError ==
        StateStoreError.BackendFailure
    let pure = projectAccumulationHistory(parent, [hash(9), hash(8)], cfg).value
    assert pure.entry.value == expected
    failHash(0)
    let plan = prepareAccumulationHistory(source, boundConfig).value
    assert plan.accumulationHistoryEntry.value.value == expectedBound
    assert array[32, byte](plan.accumulationHistoryState.value.commitment.root) == array[32, byte](
        candidate.commitment.root)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_history", 1000, before, after)
  echo "Accumulation package history passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # I/O and unexpected exceptions remain strict native failures.
except:
  quit(2)
