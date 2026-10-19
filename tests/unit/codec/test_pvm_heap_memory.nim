# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Sparse writable-range witnesses compare page counts, permissions and retained bytes to a dense oracle.
## Covers allocation preflight, address-space endpoints, immutable ownership and ARC release.

## Verification: {"arc": "pvm_heap_memory_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/machine
import ../../support/arc_evidence

## Fill every byte so a permission change cannot silently discard inaccessible or read-only storage.
proc page(index: uint32, access: PageAccess): PageImage =
  result = PageImage(index: PageIndex(index), access: access)
  for i in 0..<4096:
    result.bytes[i] = byte((uint64(index)*13 + uint64(i)) mod 251) # Independent stable byte pattern.

let empty = captureMemory([], PageLimit(0)).value
assert uint32(writablePageCount(empty, PageIndex(0), PageIndex(0x100000)).value) == 0
assert withWritablePages(empty, PageIndex(0), PageIndex(0)).error == MachineError.None
assert withWritablePages(empty, PageIndex(0x100000), PageIndex(0x100000)).error == MachineError.None
assert withWritablePages(empty, PageIndex(0), PageIndex(0x100000)).error ==
    MachineError.LimitExceeded
for endpoints in [(4'u32, 3'u32), (0'u32, 0x100001'u32), (high(uint32), high(uint32))]:
  # Reject reversed or oversized endpoints without narrowing into the physical page domain.
  assert writablePageCount(empty, PageIndex(endpoints[0]), PageIndex(endpoints[1])).error ==
    MachineError.InvalidRange
  assert withWritablePages(empty, PageIndex(endpoints[0]), PageIndex(endpoints[1])).error ==
    MachineError.InvalidRange
assert writablePageCount(default(Memory), PageIndex(0), PageIndex(0)).error ==
    MachineError.InvalidOwner
assert withWritablePages(default(Memory), PageIndex(0), PageIndex(0)).error ==
    MachineError.InvalidOwner

let original = captureMemory([page(1, PageAccess.ReadOnly), page(3, PageAccess.Inaccessible),
  page(5, PageAccess.ReadWrite), page(7, PageAccess.ReadOnly)], PageLimit(6)).value
let mapped = withWritablePages(original, PageIndex(2), PageIndex(6)).value
assert uint32(writablePageCount(original, PageIndex(0), PageIndex(8)).value) == 1
assert uint32(writablePageCount(mapped, PageIndex(2), PageIndex(6)).value) == 4
for index in 0'u32..<9'u32:
  # The exclusive boundary and all outside pages retain both access and bytes.
  let before = pageImage(original, PageIndex(index)).value
  let after = pageImage(mapped, PageIndex(index)).value
  assert before.bytes == after.bytes
  let expected = (if index >= 2 and index < 6: PageAccess.ReadWrite else: before.access)
  assert after.access == expected
assert pageImage(original, PageIndex(3)).value.access == PageAccess.Inaccessible
assert withWritablePages(mapped, PageIndex(0), PageIndex(1)).error == MachineError.LimitExceeded
let permissionsOnly = withWritablePages(mapped, PageIndex(1), PageIndex(6)).value
assert uint32(writablePageCount(permissionsOnly, PageIndex(0), PageIndex(8)).value) == 5
let edgeBase = captureMemory([], PageLimit(2)).value
let low = withWritablePages(edgeBase, PageIndex(0), PageIndex(1)).value
let edges = withWritablePages(low, PageIndex(0xfffff), PageIndex(0x100000)).value
assert uint32(writablePageCount(edges, PageIndex(0), PageIndex(0x100000)).value) == 2
assert uint32(writablePageCount(edges, PageIndex(1), PageIndex(0xfffff)).value) == 0
assert pageImage(edges, PageIndex(0xfffff)).value.bytes == default(array[4096, byte])
assert withWritablePages(edges, PageIndex(0), PageIndex(0x100000)).error ==
    MachineError.LimitExceeded

## Compare sparse operations against a small dense reference, including exact and short allocation caps.
proc referenceCycle(seed: uint32) =
  var images = newSeq[PageImage](0)
  var present = default(array[16, bool])
  var writable = default(array[16, bool])
  for index in 0..<16:
    # Deterministic mixed holes/permissions vary across runs without a production sparse lookup oracle.
    if (uint32(index)+seed) mod 3 != 0:
      let mode = PageAccess((uint32(index)*7+seed) mod 3)
      images.add(page(uint32(index), mode))
      present[index] = true
      writable[index] = mode == PageAccess.ReadWrite
  let first = int(seed mod 17)
  let past = first + int((seed*11) mod uint32(17-first))
  var total = images.len
  var expectedCount = 0'u32
  for index in first..<past:
    # Count only writable inputs, but all absent slots contribute to the allocation requirement.
    if writable[index]:
      inc expectedCount
    if not present[index]:
      inc total
  let source = captureMemory(images, PageLimit(uint32(total))).value
  assert uint32(writablePageCount(source, PageIndex(uint32(first)), PageIndex(uint32(
      past))).value) ==
    expectedCount
  let changed = withWritablePages(source, PageIndex(uint32(first)), PageIndex(uint32(past))).value
  assert uint32(writablePageCount(changed, PageIndex(uint32(first)), PageIndex(uint32(
      past))).value) ==
    uint32(past-first)
  for index in 0..<16:
    # Inspect complete pages; neither holes outside the interval nor inaccessible bytes may change.
    let prior = pageImage(source, PageIndex(uint32(index))).value
    let after = pageImage(changed, PageIndex(uint32(index))).value
    let expected = (if index >= first and index < past: PageAccess.ReadWrite else: prior.access)
    assert after.access == expected and after.bytes == prior.bytes
  if total > images.len:
    # A one-page-short owner must reject the entire change, preserving the original complete state.
    let tight = captureMemory(images, PageLimit(uint32(total-1))).value
    assert withWritablePages(tight, PageIndex(uint32(first)), PageIndex(uint32(past))).error ==
      MachineError.LimitExceeded
    assert uint32(writablePageCount(tight, PageIndex(uint32(first)), PageIndex(uint32(
        past))).value) ==
      expectedCount
  let again = withWritablePages(changed, PageIndex(uint32(first)), PageIndex(uint32(past))).value
  assert uint32(writablePageCount(again, PageIndex(uint32(first)), PageIndex(uint32(
      past))).value) ==
    uint32(past-first)

for seed in 0'u32..<128'u32:
  referenceCycle(seed) # Cover sparse holes, permission-only changes, empty ranges and exact limits.

## Retain successor owners after locals disappear and isolate later guest writes from both ancestors.
proc retained(): Memory =
  let source = captureMemory([page(16, PageAccess.Inaccessible)], PageLimit(3)).value
  let mapped = withWritablePages(source, PageIndex(16), PageIndex(19)).value
  let changed = store(mapped, MemoryAddress(65536), AccessWidth(1), RegisterValue(255)).value
  assert pageImage(source, PageIndex(16)).value.access == PageAccess.Inaccessible
  assert pageImage(mapped, PageIndex(16)).value.bytes[0] == byte(208)
  changed
assert pageImage(retained(), PageIndex(16)).value.bytes[0] == 255
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Complete owner graphs, shared pages and changed pages must all release under ARC.
  referenceCycle(uint32(iteration mod 128))
  discard retained()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_heap_memory", 1000, before, after)
echo "PVM heap memory passed"
echo "ARC_RELEASE cycles=1000 unchanged"
