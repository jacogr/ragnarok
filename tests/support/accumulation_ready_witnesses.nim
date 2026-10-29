# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal ready-ring framing tests the canonical projection, dependency edits and elapsed-slot expiry.

import std/assertions
import ../../src/state/accumulation/ready as accumulation_ready
import ../../src/state/store
import ../../src/codec/[bounded, composite, owned, report_owned]
import ../../src/codec/work/report as work_report
import ../../src/codec/header
import ../../src/codec/state/[safrole as state_safrole, workqueues as state_workqueues,
    layout as state_layout, trie as state_trie]
import ./report_context

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc readyPolicy*(slots = 12'u64): AccumulationReadyConfig =
  ## Inspected work and complete output framing have separate finite ceilings.
  AccumulationReadyConfig(items: ElementLimit(100), dependencies: ElementLimit(40),
      queues: WorkQueueConfig(epochSlots: EpochSlots(slots), cores: CoreCount(2),
          perSlot: ElementLimit(10), totalItems: ElementLimit(20),
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
proc parent(rows: seq[ReadyRow], policy: AccumulationReadyConfig): ReadySnapshot =
  ## Only input capture uses the existing codec; expected output framing is emitted literally.
  let entry = readyStateEntry(rows, policy.queues).value
  decodeReadyState(entry.value, policy.queues).value.snapshot
proc history(rows: seq[AccumulatedRow], policy: AccumulationReadyConfig): AccumulatedSnapshot =
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
  let result = projectAccumulationReady(original, accumulated, available, processed, HeaderSlot(3),
      HeaderSlot(6), policy).value
  assert result.entry.value == expected
  var copied = result.entry
  copied.value[0] = 99
  assert result.ring.readySlotCount(WorkQueueSlot(0)).value == 0
  assert result.ring.readyDependencyAt(WorkQueueSlot(3), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes == key(9).bytes
  var short = policy
  short.items = ElementLimit(17) # Five old reports, three history hashes, six incoming and four processed consume eighteen.
  assert projectAccumulationReady(original, accumulated, available, processed, HeaderSlot(3),
    HeaderSlot(6), short).error == AccumulationReadyError.LimitExceeded
  short = policy
  short.dependencies = ElementLimit(12) # Prerequisite/lookup overlap counts before subtraction.
  assert projectAccumulationReady(original, accumulated, available, processed, HeaderSlot(3),
    HeaderSlot(6), short).error == AccumulationReadyError.LimitExceeded
  assert projectAccumulationReady(original, accumulated, [default(OwnedReport)], [], HeaderSlot(3),
      HeaderSlot(6), policy).error == AccumulationReadyError.InvalidReport
  assert projectAccumulationReady(original, accumulated, [wrongCore], [], HeaderSlot(3), HeaderSlot(
      6), policy).error == AccumulationReadyError.InvalidReport
  assert projectAccumulationReady(original, accumulated, [wrongShards], [], HeaderSlot(3),
      HeaderSlot(6), policy).error == AccumulationReadyError.InvalidReport
  assert projectAccumulationReady(broaderParent, accumulated, [], [], HeaderSlot(3), HeaderSlot(6),
      policy).error == AccumulationReadyError.InvalidReport
  assert projectAccumulationReady(default(ReadySnapshot), accumulated, [], [], HeaderSlot(3),
      HeaderSlot(6), policy).error == AccumulationReadyError.InvalidState
  assert projectAccumulationReady(original, default(AccumulatedSnapshot), [], [], HeaderSlot(3),
      HeaderSlot(6), policy).error == AccumulationReadyError.InvalidState
  for target in [2'u32, 3]:
    assert projectAccumulationReady(original, accumulated, [], [], HeaderSlot(3), HeaderSlot(
        target), policy).error == AccumulationReadyError.InvalidTime
  var invalid = policy
  invalid.queues.epochSlots = EpochSlots(0)
  assert projectAccumulationReady(original, accumulated, [], [], HeaderSlot(3), HeaderSlot(6),
      invalid).error == AccumulationReadyError.InvalidConfig
  failHash(0)
  let simple = parent(@[@[ReadyItem(report: a)], @[ReadyItem(report: b)], @[ReadyItem(report: c)],
      @[ReadyItem(report: d)]], policy)
  let noHistory = history(newSeq[AccumulatedRow](4), policy)
  failHash(3)
  for index, target in [4'u32, 5, 6, 7, 8, high(uint32)]:
    let mask = [14, 12, 8, 0, 0, 0][index]
    let queue = projectAccumulationReady(simple, noHistory, [], [], HeaderSlot(3), HeaderSlot(
        target), policy).value.ring
    for slot in 0..<4:
      assert queue.readySlotCount(WorkQueueSlot(uint64(slot))).value == (if (mask and (
          1 shl slot)) != 0: 1 else: 0)
  assert hashCalls() == 0
  failHash(0)
  let singletonPolicy = readyPolicy(1)
  let singleton = parent(@[@[ReadyItem(report: a)]], singletonPolicy)
  let singletonHistory = history(newSeq[AccumulatedRow](1), singletonPolicy)
  let replaced = projectAccumulationReady(singleton, singletonHistory, [n0], [], HeaderSlot(1),
      HeaderSlot(2), singletonPolicy).value
  assert replaced.ring.readySlotCount(WorkQueueSlot(0)).value == 1
  assert replaced.ring.readyItemAt(WorkQueueSlot(0), ReadyItemIndex(0)).value.dependencies == 3
