# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native tests for deterministic E/Q, published input projections, bounds and retained ownership.
##
## Hastur main replays 262 independent queue expectations, literal ordering/refusal cases, a genuine
## signed block-admission binding and 1,000 ARC release cycles; no production APIs are defined.

# @@Verification={"arc": "accumulation_queue_arc_release"}

import std/assertions
import std/envvars
import std/strutils
import std/syncio
import std/sequtils
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/availability as state_availability
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/owned as codec_owned
import ../../../src/codec/work_report as codec_work_report
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/header as codec_header
import ../../support/state_report_context
import ../../support/state_report_admission_context
import ../../support/testing_arc_evidence

## Poison hashing only after genuine inputs exist, proving planning has no backend/write side effects.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

## Small bounded profile also permits aggregate incoming and historical descriptors.
proc cfg(cores = 2'u64, slots = 12'u64): AccumulationQueueConfig =
  result = AccumulationQueueConfig(queues: config().packages.queues,
    items: ElementLimit(10000), dependencies: ElementLimit(80000))
  result.queues.cores = CoreCount(cores)
  result.queues.epochSlots = EpochSlots(slots)
  result.queues.totalItems = ElementLimit(10000)
  result.queues.perSlot = ElementLimit(10000)
  result.queues.totalDependencies = ElementLimit(80000)
  result.queues.perDependencies = ElementLimit(10000)

## Authored fixed package identity remains distinct from every root and ring ordinal.
func key(value: byte): PackageHash =
  result = PackageHash(bytes: default(array[32, byte]))
  result.bytes[0] = value

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

## Plan over authored canonical state without substituting full-block admission certificates.
proc plan(values: openArray[OwnedReport], rows: openArray[ReadyRow], history: openArray[
    AccumulatedRow], slot = 2'u32, policy = cfg()): AccumulationQueueResult[AccumulationQueuePlan] =
  let ready = readyStateEntry(rows, cfg().queues).value.value
  let accumulated = accumulatedStateEntry(history, cfg().queues).value.value
  planAccumulationQueues(values, ready, accumulated, HeaderSlot(slot), policy)

## Compare exact ordered nominal identities, not merely a set of selected reports.
proc sequence(owner: AccumulationQueuePlan, ids: openArray[byte]) =
  assert owner.accumulationCount.value == ids.len, "count " & $owner.accumulationCount.value &
      " expected " & $ids.len
  # Report sequence order matters independently of set membership.
  for i in 0..<ids.len:
    assert ownedReportInfo(owner.accumulationAt(AccumulationIndex(
        i)).value).value.header.packageHash.bytes ==
      key(ids[i]).bytes, "sequence index " & $i # Retained complete reports carry the expected priority order.

## E, whole-wave Q, ring rotation, historical removal and lookup-key union each have literal answers.
proc authoredCases(base: OwnedReport): AccumulationQueuePlan =
  var rows = newSeq[ReadyRow](12)
  var history = newSeq[AccumulatedRow](12)
  rows[2] = @[ReadyItem(report: report(base, 5), dependencies: @[key(1)])]
  rows[3] = @[ReadyItem(report: report(base, 6))]
  rows[0] = @[ReadyItem(report: report(base, 7), dependencies: @[key(5)]),
    ReadyItem(report: report(base, 11), dependencies: @[key(8)])]
  history[1] = @[key(8), key(9)]
  history[9] = @[key(8)] # Cross-slot repeated hashes represent an ordinary history union.
  let values = @[report(base, 1), report(base, 2), report(base, 3, [key(1)]),
    report(base, 4, [key(3)]), report(base, 9, [key(8)]), report(base, 10, [key(8)])]
  let outcome = plan(values, rows, history)
  assert outcome.error == AccumulationQueueError.None
  result = outcome.value
  sequence(result, [1'u8, 2, 5, 6, 3, 10, 7, 4])
  assert result.accumulationImmediateCount.value == 2
  assert result.accumulationQueuedCount.value == 7
  assert result.accumulationQueuedAt(AccumulationIndex(3)).value.dependencies == 1
  assert result.accumulationDependencyAt(AccumulationIndex(3), WorkQueueHashIndex(0)).value.bytes ==
      key(8).bytes
  # Candidate modulo, rather than parent position or elapsed-slot expiration, controls parent priority.
  let rotated = plan([], rows, history, 3).value
  sequence(rotated, [6'u8])
  let wrapped = plan([], rows, history, 15).value
  sequence(wrapped, [6'u8])
  let lookup = SegmentLookup(packageHash: key(1), segmentRoot: default(SegmentRoot))
  let union = plan([report(base, 12, [key(1)], [lookup])], newSeq[ReadyRow](12),
    newSeq[AccumulatedRow](12)).value
  assert union.accumulationQueuedAt(AccumulationIndex(0)).value.dependencies == 1
  assert union.accumulationDependencyAt(AccumulationIndex(0), WorkQueueHashIndex(0)).value.bytes ==
      key(1).bytes
  sequence(union, []) # Overlapping prerequisite and lookup key is one unsatisfied identity, never a root.
  # Self/cyclic/unavailable dependency graphs terminate without fabricating executable work.
  let cyclic = plan([report(base, 1, [key(2)]), report(base, 2, [key(1)]),
    report(base, 3, [key(3)])], newSeq[ReadyRow](12), newSeq[AccumulatedRow](12)).value
  sequence(cyclic, [])
  # Literal Q includes all ready duplicates in a wave and E suppresses the blocked duplicate afterward.
  rows = newSeq[ReadyRow](12)
  rows[2] = @[ReadyItem(report: report(base, 1)), ReadyItem(report: report(base, 1)),
    ReadyItem(report: report(base, 1), dependencies: @[key(4)])]
  sequence(plan([], rows, history).value, [1'u8, 1])
  # Immediate records bypass history removal, as the specification's partition explicitly requires.
  history[0] = @[key(1)]
  sequence(plan([report(base, 1)], rows, history).value, [1'u8])

## Replay six original pinned inputs plus independently generated cyclic/acyclic graph expectations.
proc projections() {.raises.} =
  var total = 0
  for line in readFile(getEnv("RAGNAROK_ACCUMULATION_QUEUE")).splitLines:
    if line.len == 0: continue # Ignore only the trailing transport newline.
    let f = line.splitWhitespace
    let policy = cfg(uint64(parseInt(f[1])), uint64(parseInt(f[2])))
    var values: seq[OwnedReport] = @[]
    # An explicit empty fixture field must remain an empty available sequence.
    if f[6] != "-":
      # Capture every original full report under the selected profile.
      for raw in f[6].split(','): values.add(decodeOwnedReport(unhex(raw), uint64(
          policy.queues.cores)).value)
    var ready = unhex(f[4])
    var history = unhex(f[5])
    let outcome = planAccumulationQueues(values, ready, history, HeaderSlot(parseInt(f[3])), policy)
    assert outcome.error == AccumulationQueueError.None, f[0] & " " & $outcome.error
    let owner = outcome.value
    assert owner.accumulationImmediateCount.value == parseInt(f[7]), f[0]
    let expected = if f[8] == "-": newSeq[string](0) else: f[8].split(',')
    assert owner.accumulationCount.value == expected.len, f[0]
    # Compare full report bytes, not just identities.
    for i in 0..<expected.len:
      assert reportBytes(owner.accumulationAt(AccumulationIndex(i)).value) == unhex(expected[i]), f[0]
    let pending = if f[9] == "-": newSeq[string](0) else: f[9].split(',')
    assert owner.accumulationQueuedCount.value == pending.len, f[0]
    # Independently verify every initial q report and remaining dependency set.
    for i in 0..<pending.len:
      let fields = pending[i].split(':')
      let item = owner.accumulationQueuedAt(AccumulationIndex(i)).value
      assert @(ownedReportInfo(item.report).value.header.packageHash.bytes) == unhex(fields[0])
      let deps = if fields[1] == "-": newSeq[byte](0) else: unhex(fields[1])
      assert item.dependencies == deps.len div 32
      # Dependencies remain attached to this queue item after selection.
      for j in 0..<item.dependencies:
        let actual = owner.accumulationDependencyAt(AccumulationIndex(i), WorkQueueHashIndex(j)).value
        for k in 0..<32: assert actual.bytes[k] == deps[j*32+k] # Full edited q, not only executable output.
    for i in 0..<ready.len: ready[i] = 0 # Caller mutation cannot change captured report bytes/queue decisions.
    for i in 0..<history.len: history[i] = 255 # Independent owner capture also covers C(15).
    # Recheck after source mutation rather than relying on pre-mutation observations alone.
    for i in 0..<expected.len:
      assert reportBytes(owner.accumulationAt(AccumulationIndex(i)).value) == unhex(expected[i]), f[0]
    inc total
  assert total == 262

## Invalid owners, exact-consumption failures, hostile count framing and independent budgets carry no plan.
proc boundaries(base: OwnedReport) =
  let empty = newSeq[byte](12)
  let policy = cfg()
  assert planAccumulationQueues([default(OwnedReport)], empty, empty, HeaderSlot(0),
      policy).error == AccumulationQueueError.InvalidReport
  assert planAccumulationQueues([], empty, empty, HeaderSlot(0), default(
      AccumulationQueueConfig)).error == AccumulationQueueError.InvalidConfig
  assert planAccumulationQueues([], newSeq[byte](13), empty, HeaderSlot(0), policy).error ==
      AccumulationQueueError.InvalidState
  assert planAccumulationQueues([], empty, newSeq[byte](13), HeaderSlot(0), policy).error ==
      AccumulationQueueError.InvalidState
  # Every truncated fixed-ring prefix refuses without exposing a partial owner.
  for cut in 0..<empty.len:
    let short = empty.toOpenArray(0, cut-1)
    assert planAccumulationQueues([], short, empty, HeaderSlot(0), policy).error !=
        AccumulationQueueError.None
    assert planAccumulationQueues([], empty, short, HeaderSlot(0), policy).error !=
        AccumulationQueueError.None
  var limited = policy
  limited.items = ElementLimit(0)
  assert planAccumulationQueues([base], empty, empty, HeaderSlot(0), limited).error ==
      AccumulationQueueError.LimitExceeded
  limited = policy
  limited.dependencies = ElementLimit(0)
  assert planAccumulationQueues([report(base, 1, [key(2)])], empty, empty, HeaderSlot(0),
      limited).error == AccumulationQueueError.LimitExceeded
  limited = policy
  limited.queues.reportBytes = ByteLimit(1)
  assert planAccumulationQueues([base], empty, empty, HeaderSlot(0), limited).error ==
      AccumulationQueueError.LimitExceeded
  limited = policy
  limited.items = ElementLimit(high(uint64))
  assert planAccumulationQueues([], empty, empty, HeaderSlot(0), limited).error ==
      AccumulationQueueError.InvalidConfig
  assert default(AccumulationQueuePlan).accumulationCount.error ==
      AccumulationQueueError.Uninitialized
  assert default(AccumulationQueuePlan).accumulationImmediateCount.error ==
      AccumulationQueueError.Uninitialized
  assert default(AccumulationQueuePlan).accumulationQueuedCount.error ==
      AccumulationQueueError.Uninitialized
  assert default(AccumulationQueuePlan).accumulationAt(AccumulationIndex(0)).error ==
      AccumulationQueueError.Uninitialized
  assert default(AccumulationQueuePlan).accumulationQueuedAt(AccumulationIndex(0)).error ==
      AccumulationQueueError.Uninitialized
  assert default(AccumulationQueuePlan).accumulationDependencyAt(AccumulationIndex(0),
      WorkQueueHashIndex(0)).error == AccumulationQueueError.Uninitialized
  assert default(BlockAccumulationQueue).accumulationProjection.error ==
      AccumulationQueueError.Uninitialized
  assert default(BlockAccumulationQueue).accumulationAdmission.error ==
      AccumulationQueueError.Uninitialized
  let one = planAccumulationQueues([base], empty, empty, HeaderSlot(high(uint32)), policy).value
  assert one.accumulationAt(AccumulationIndex(high(uint64))).error ==
      AccumulationQueueError.InvalidIndex
  assert one.accumulationQueuedAt(AccumulationIndex(0)).error == AccumulationQueueError.InvalidIndex
  assert one.accumulationDependencyAt(AccumulationIndex(0), WorkQueueHashIndex(0)).error ==
      AccumulationQueueError.InvalidIndex
  assert planBlockAccumulationQueue(default(AdmittedReports), policy).error ==
      AccumulationQueueError.InvalidAdmission

## Genuine Ed25519 assurances feed exactly one old report through completed admission; no state writes/hashes occur.
proc boundCase(base: OwnedReport): BlockAccumulationQueue =
  var signedOptions0 = signedBlockFixtureConfig()
  signedOptions0.withAvailable = true
  let context = authored(base, signedOptions0)
  assert context.staged.value.availability.availableReportCount == 1
  let admission = planBlockReports(context.staged, context.older, config())
  assert admission.error == ReportAdmissionError.None
  let before = context.original.snapshot.value.commitment.root
  failHash(1)
  let planned = planBlockAccumulationQueue(admission.value, cfg())
  failHash(0)
  assert planned.error == AccumulationQueueError.None
  result = planned.value
  let owner = result.accumulationProjection.value
  assert owner.accumulationCount.value == 1
  assert reportBytes(owner.accumulationAt(AccumulationIndex(0)).value) == reportBytes(
    context.staged.value.availability.availableReportAt(0).value)
  assert result.accumulationAdmission.value.reportBlockStage.error == ReportAdmissionError.None
  assert array[32, byte](context.original.snapshot.value.commitment.root) == array[32, byte](before)
  var other = cfg()
  other.queues.epochSlots = EpochSlots(600)
  assert planBlockAccumulationQueue(admission.value, other).error ==
      AccumulationQueueError.InvalidConfig
  other = cfg()
  other.items = ElementLimit(0)
  assert planBlockAccumulationQueue(admission.value, other).error ==
      AccumulationQueueError.LimitExceeded

## Release private plans and all captured reports after repeated successful and refused construction.
proc lifetime(base: OwnedReport) =
  let empty = newSeq[byte](12)
  discard planAccumulationQueues([base], empty, empty, HeaderSlot(0), cfg()) # Warm runtime allocations first.
  let before = getOccupiedMem()
  # Repeated success and late owner refusal must release all per-call scratch.
  for i in 0..<1000:
    let accepted = planAccumulationQueues([base], empty, empty, HeaderSlot(0), cfg())
    assert accepted.error == AccumulationQueueError.None
    let refused = planAccumulationQueues([default(OwnedReport)], empty, empty, HeaderSlot(0), cfg())
    assert refused.error == AccumulationQueueError.InvalidReport
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_queue", 1000, before, after)

## Each selected phase exercises native assertions through the supported Hastur runner.
proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i in 0..<raw.len: wire[i] = byte(raw[i]) # Preserve exact binary fixture bytes.
  let base = decodeOwnedReport(wire, 2).value
  let escaped = authoredCases(base)
  projections()
  boundaries(base)
  let bound = boundCase(base)
  assert bound.accumulationProjection.value.accumulationAt(AccumulationIndex(0)).error ==
      AccumulationQueueError.None
  sequence(escaped, [1'u8, 2, 5, 6, 3, 10, 7, 4]) # Parent/source scopes have already ended.
  lifetime(base)
  echo "PASS accumulation queue: E/Q waves, 262 projections, bounds, admission binding and ARC release"
try:
  main() # Execute every assertion through the native runner.
except:
  quit(2) # Unexpected fixture/transport errors are failures, never empty successes.
