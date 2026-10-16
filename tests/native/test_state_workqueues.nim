## Supplementary ring/source/copy/child-lifetime, typed owner/index and failure-guard contracts.
import std/[assertions, cmdline, syncio]
import ../../src/codec/[state_workqueues, report_owned, owned, bounded]

## Scope exit must not release the child report retained through a copied item observation.
proc detached(report: OwnedReport, config: WorkQueueConfig): OwnedReport =
  var rows = newSeq[ReadyRow](2)
  rows[1] = @[ReadyItem(report: report)]
  let entry = readyStateEntry(rows, config)
  assert entry.error == WorkQueueError.None
  var bytes = entry.value.value
  let parsed = decodeReadyState(bytes, config)
  assert parsed.error == WorkQueueError.None
  result = readyItemAt(parsed.value.snapshot, WorkQueueSlot(1), ReadyItemIndex(0)).value.report
  for i in 0..<bytes.len: bytes[i] = 0 # Child remains independent after parent and local arrays leave scope.

## Check independent parent/source hashes and child ownership, including all default and index error paths.
proc main() {.raises.} =
  assert sizeof(int) == 8 and sizeof(ReadyRow) == 16 and sizeof(ReadyItem) == 24
  let config = WorkQueueConfig(epochSlots: EpochSlots(2), cores: CoreCount(2),
      perSlot: ElementLimit(3),
    totalItems: ElementLimit(3), perDependencies: ElementLimit(3), totalDependencies: ElementLimit(4),
    reportBytes: ByteLimit(100000), maxBytes: ByteLimit(100000))
  let text = readFile(paramStr(1))
  var bytes = newSeq[byte](text.len)
  for i in 0..<bytes.len: bytes[i] = byte(text[i]) # Authored fixture bytes, independent of parent construction.
  let report = decodeOwnedReport(bytes, 2)
  assert report.error == OwnershipError.None
  var a = default(PackageHash)
  var b = default(PackageHash)
  a.bytes[0] = 17
  b.bytes[0] = 18
  var rows = newSeq[ReadyRow](2)
  rows[1] = @[ReadyItem(report: report.value, dependencies: @[a, b])]
  let entry = readyStateEntry(rows, config)
  assert entry.error == WorkQueueError.None and array[31, byte](entry.value.key)[0] == 14
  rows[1][0].dependencies[0] = default(PackageHash)
  rows[1][0].report = default(OwnedReport)
  var wire = entry.value.value
  let parsed = decodeReadyState(wire, config)
  assert parsed.error == WorkQueueError.None and parsed.value.consumed == wire.len
  let owner = parsed.value.snapshot
  for i in 0..<wire.len: wire[i] = 0 # Whole capture precedes input destruction.
  assert readyInfo(owner).value.items == 1 and readyInfo(owner).value.dependencies == 2
  assert readySlotCount(owner, WorkQueueSlot(0)).value == 0
  assert readyDependencyAt(owner, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 17
  var copy = readyDependencyAt(owner, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(0)).value
  copy.bytes[0] = 0
  assert readyDependencyAt(owner, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 17
  let child = detached(report.value, config)
  var output = newSeq[byte](bytes.len)
  assert encodeOwnedReport(child, output).error == OwnershipError.None and output == bytes
  var replaced = owner
  replaced = default(ReadySnapshot)
  assert readyInfo(owner).value.items == 1
  let badSlot = readySlotCount(owner, WorkQueueSlot(high(uint64)))
  assert badSlot.error == WorkQueueError.InvalidIndex
  var accumulated = newSeq[AccumulatedRow](2)
  accumulated[0] = @[a, b]
  let history = accumulatedStateEntry(accumulated, config)
  assert history.error == WorkQueueError.None and array[31, byte](history.value.key)[0] == 15
  accumulated[0][0] = default(PackageHash)
  wire = history.value.value
  let decoded = decodeAccumulatedState(wire, config)
  assert decoded.error == WorkQueueError.None
  for i in 0..<wire.len: wire[i] = 0 # Fixed history identities cannot depend on caller bytes.
  assert accumulatedInfo(decoded.value.snapshot).value.items == 2
  assert accumulatedHashAt(decoded.value.snapshot, WorkQueueSlot(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 17
  let late = decodeReadyState(entry.value.value.toOpenArray(0, entry.value.value.len-2), config)
  assert late.error == WorkQueueError.Truncated
  echo "PASS work queues: retained rings/reports, independent sets, detached child and result/index guards"

# Fixture I/O is trusted setup and must fail explicitly if unavailable.
try:
  main()
except:
  # A missing report fixture cannot count as codec coverage.
  quit 2
