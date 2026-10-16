## Supplementary ring/source/copy/child-lifetime, typed owner/index and failure-guard contracts.
import std/os
import ../../src/[state_workqueues, report_owned, owned, bounded]

## A failed/default tagged result must reject reads of its inactive success payload under checked LTO.
proc guarded[T](value: WorkQueueResult[T]) =
  var caught = false
  try:
    discard value.value # Failed alternatives cannot fabricate arrays, child reports or consumed extents.
  except FieldDefect:
    caught = true # Runtime variant checks remain active in optimized builds.
  doAssert caught

## Scope exit must not release the child report retained through a copied item observation.
proc detached(report: OwnedReport, config: WorkQueueConfig): OwnedReport =
  var rows = newSeq[ReadyRow](2)
  rows[1] = @[ReadyItem(report: report)]
  let entry = readyStateEntry(rows, config)
  doAssert entry.error == WorkQueueError.None
  var bytes = entry.value.value
  let parsed = decodeReadyState(bytes, config)
  doAssert parsed.error == WorkQueueError.None
  result = readyItemAt(parsed.value.snapshot, WorkQueueSlot(1), ReadyItemIndex(0)).value.report
  for i in 0..<bytes.len: bytes[i] = 0 # Child remains independent after parent and local arrays leave scope.

## Check independent parent/source hashes and child ownership, including all default and index error paths.
proc main() =
  doAssert sizeof(int) == 8 and sizeof(ReadyRow) == 16 and sizeof(ReadyItem) == 24
  let config = WorkQueueConfig(epochSlots: EpochSlots(2), cores: CoreCount(2),
      perSlot: ElementLimit(3),
    totalItems: ElementLimit(3), perDependencies: ElementLimit(3), totalDependencies: ElementLimit(4),
    reportBytes: ByteLimit(100000), maxBytes: ByteLimit(100000))
  let text = readFile(paramStr(1))
  var bytes = newSeq[byte](text.len)
  for i in 0..<bytes.len: bytes[i] = byte(text[i]) # Authored fixture bytes, independent of parent construction.
  let report = decodeOwnedReport(bytes, 2)
  doAssert report.error == OwnershipError.None
  var a, b: PackageHash
  a.bytes[0] = 17
  b.bytes[0] = 18
  var rows = newSeq[ReadyRow](2)
  rows[1] = @[ReadyItem(report: report.value, dependencies: @[a, b])]
  let entry = readyStateEntry(rows, config)
  doAssert entry.error == WorkQueueError.None and array[31, byte](entry.value.key)[0] == 14
  rows[1][0].dependencies[0] = default(PackageHash)
  rows[1][0].report = default(OwnedReport)
  var wire = entry.value.value
  let parsed = decodeReadyState(wire, config)
  doAssert parsed.error == WorkQueueError.None and parsed.value.consumed == wire.len
  let owner = parsed.value.snapshot
  for i in 0..<wire.len: wire[i] = 0 # Whole capture precedes input destruction.
  doAssert readyInfo(owner).value.items == 1 and readyInfo(owner).value.dependencies == 2
  doAssert readySlotCount(owner, WorkQueueSlot(0)).value == 0
  doAssert readyDependencyAt(owner, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 17
  var copy = readyDependencyAt(owner, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(0)).value
  copy.bytes[0] = 0
  doAssert readyDependencyAt(owner, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 17
  let child = detached(report.value, config)
  var output = newSeq[byte](bytes.len)
  doAssert encodeOwnedReport(child, output).error == OwnershipError.None and output == bytes
  var replaced = owner
  replaced = default(ReadySnapshot)
  guarded(readyInfo(replaced))
  guarded(readySlotCount(replaced, WorkQueueSlot(0)))
  guarded(readyItemAt(replaced, WorkQueueSlot(0), ReadyItemIndex(0)))
  guarded(readyDependencyAt(replaced, WorkQueueSlot(0), ReadyItemIndex(0), WorkQueueHashIndex(0)))
  doAssert readyInfo(owner).value.items == 1
  let badSlot = readySlotCount(owner, WorkQueueSlot(high(uint64)))
  doAssert badSlot.error == WorkQueueError.InvalidIndex
  guarded(badSlot)
  guarded(readyItemAt(owner, WorkQueueSlot(0), ReadyItemIndex(0)))
  guarded(readyDependencyAt(owner, WorkQueueSlot(1), ReadyItemIndex(0), WorkQueueHashIndex(2)))
  var accumulated = newSeq[AccumulatedRow](2)
  accumulated[0] = @[a, b]
  let history = accumulatedStateEntry(accumulated, config)
  doAssert history.error == WorkQueueError.None and array[31, byte](history.value.key)[0] == 15
  accumulated[0][0] = default(PackageHash)
  wire = history.value.value
  let decoded = decodeAccumulatedState(wire, config)
  doAssert decoded.error == WorkQueueError.None
  for i in 0..<wire.len: wire[i] = 0 # Fixed history identities cannot depend on caller bytes.
  doAssert accumulatedInfo(decoded.value.snapshot).value.items == 2
  doAssert accumulatedHashAt(decoded.value.snapshot, WorkQueueSlot(0), WorkQueueHashIndex(
      0)).value.bytes[0] == 17
  guarded(accumulatedInfo(default(AccumulatedSnapshot)))
  guarded(accumulatedSlotCount(default(AccumulatedSnapshot), WorkQueueSlot(0)))
  guarded(accumulatedHashAt(default(AccumulatedSnapshot), WorkQueueSlot(0), WorkQueueHashIndex(0)))
  guarded(accumulatedHashAt(decoded.value.snapshot, WorkQueueSlot(1), WorkQueueHashIndex(0)))
  guarded(default(WorkQueueResult[WorkQueueRead[ReadySnapshot]]))
  let late = decodeReadyState(entry.value.value.toOpenArray(0, entry.value.value.len-2), config)
  doAssert late.error == WorkQueueError.Truncated
  guarded(late)
  echo "PASS work queues: retained rings/reports, independent sets, detached child and result/index guards"

main()
