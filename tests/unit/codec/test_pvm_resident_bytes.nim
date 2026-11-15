# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual first-RW owners preserve complete zeroed bytes, moves, refusal and exact lifetime charges.

# @@Verification={"arc":"pvm_resident_bytes_arc_release"}

import std/[assertions, syncio]
import ../../../src/pvm/internal/resident_bytes
import ../../support/arc_evidence

type
  StorageCellData = object
    ## A real ARC heap payload owns cold storage without a back-reference or hidden clone.
    storage: RWStorage
  StorageCell = ref StorageCellData

proc `=copy`(destination: var StorageCellData, source: StorageCellData) {.error.}
  ## A heap payload must transfer, rather than duplicate, its actual owning storage child.

proc `=dup`(source: StorageCellData): StorageCellData {.error.}
  ## Direct payload duplication is forbidden independently of the managed handle's identity.

proc fillWindow(output: var openArray[byte]) =
  ## Mutate exactly a scoped caller slice; no owning container or resize authority is acquired.
  for index in 0..<output.len:
    output[index] = byte(201+index)

proc checkScalarTransfers[W: static[int]](view: var RWView) =
  ## Managed and mapped owners share exact little-endian, unaligned and whole-extent behavior.
  ## Every successful test store restores its original bytes before the enclosing owner test resumes.
  assert view.len >= 8
  var before = newSeq[byte](view.len)
  for index in 0..<view.len: before[index] = view[index]
  for at in [0, 1, view.len-W]:
    # Independent byte accumulation checks zero extension and the final legal access.
    var expected = 0'u64
    for index in 0..<W: expected = expected or (uint64(before[at+index]) shl (index*8))
    var observed = 0xfedcba9876543210'u64
    assert tryReadScalar[W](view, at, observed) and observed == expected
  for at in [-1, view.len-W+1, high(int)]:
    # Neither output nor any byte may change when the complete transfer does not fit.
    var observed = 0xfedcba9876543210'u64
    assert not tryReadScalar[W](view, at, observed) and observed == 0xfedcba9876543210'u64
    assert not tryWriteScalar[W](view, at, 0x0123456789abcdef'u64)
    for index in 0..<view.len: assert view[index] == before[index]
  for at in [1, view.len-W, (if view.len > 4103: 4095 else: 1)]:
    # A disjoint literal exercises truncation, unaligned/page-crossing stores and unchanged neighbors.
    assert tryWriteScalar[W](view, at, 0x0123456789abcdef'u64)
    for index in 0..<view.len:
      assert view[index] == (if index >= at and index < at+W:
        byte((0x0123456789abcdef'u64 shr ((index-at)*8)) and 255) else: before[index])
    for index in 0..<view.len: view[index] = before[index]

proc checkEmptyScalarTransfers() =
  ## Empty and malformed test borrows return failure rather than an assertion or fabricated value.
  var view = default(RWView)
  var value = 0xfedcba9876543210'u64
  assert not tryReadScalar[1](view, 0, value) and value == 0xfedcba9876543210'u64
  assert not tryWriteScalar[8](view, 0, 0)
  assert residentWitnessNullScalar()

proc checkManaged() =
  ## The legacy alternative supplies the same indexed/sliced bytes without a foreign charge.
  let before = residentWitnessSnapshot()
  var bytes = newSeq[byte](1031)
  for index in 0..<bytes.len:
    bytes[index] = byte(index mod 251)
  var storage = takeManaged(bytes)
  assert bytes.len == 0
  assert storage.len == 1031 and storage.logicalBytes == 1031 and storage.mappedBytes == 0
  block:
    # The borrow ends before storage retirement; writes are observed through independent reads.
    var view = borrowRW(storage)
    checkScalarTransfers[1](view)
    checkScalarTransfers[2](view)
    checkScalarTransfers[4](view)
    checkScalarTransfers[8](view)
    assert view.len == 1031 and borrowedData(view) != nil
    for index in 0..<view.len:
      assert view[index] == byte(index mod 251)
    view[0] = 91
    view[1030] = 173
    # Native locations alias the owner rather than an indexed byte-value temporary.
    let last = view.borrowedData(1030)
    last[] = 174
    assert view[1030] == 174
    view[1030] = 173
    assert last[] == 173
    fillWindow(view.toOpenArray(512, 515))
    assert view[0] == 91 and view[1030] == 173
    assert view[511] == byte(511 mod 251) and view[516] == byte(516 mod 251)
    for index in 0..<4:
      assert view[512+index] == byte(201+index)
  let after = residentWitnessSnapshot()
  assert after == before

proc checkDefaults() =
  ## Default/empty/invalid values never acquire release authority or fabricate a visible extent.
  checkEmptyScalarTransfers()
  var storage = default(RWStorage)
  assert storage.len == 0 and storage.logicalBytes == 0 and storage.mappedBytes == 0
  let view = borrowRW(storage)
  assert view.len == 0 and borrowedData(view) == nil
  let invalid = tryMapFreshZero(-1)
  assert invalid.error == ResidentAllocationError.InvalidSize
  let uninitialized = default(ResidentAllocationResult)
  assert uninitialized.error == ResidentAllocationError.Uninitialized
  when FreshRWProfileEnabled:
    # Empty success neither maps nor holds a positive accounting extent.
    let before = residentWitnessSnapshot()
    var empty = tryMapFreshZero(0)
    assert empty.error == ResidentAllocationError.None
    var owner = takeOwned(empty)
    assert empty.error == ResidentAllocationError.Uninitialized
    let emptyView = borrowRW(owner)
    assert emptyView.len == 0 and borrowedData(emptyView) == nil
    assert residentWitnessSnapshot() == before

proc foreignCycle(bytes: int) =
  ## One complete map->storage->heap->storage->drop path keeps exact extents until final release.
  assert bytes > 4096
  let before = residentWitnessSnapshot()
  var allocation = tryMapFreshZero(bytes)
  assert allocation.error == ResidentAllocationError.None
  var owner = takeOwned(allocation)
  assert allocation.error == ResidentAllocationError.Uninitialized
  block:
    # Verify the complete requested span, including its final partial guest/host page.
    var view = borrowRW(owner)
    assert view.len == bytes
    checkScalarTransfers[1](view)
    checkScalarTransfers[2](view)
    checkScalarTransfers[4](view)
    checkScalarTransfers[8](view)
    for index in 0..<view.len:
      assert view[index] == 0
    view[0] = 7
    view[4095] = 149
    view[bytes-1] = 239
    # The final byte of a resident mapping has the same scoped pointer contract.
    let last = view.borrowedData(bytes-1)
    assert last[] == 239
    last[] = 238
    assert view[bytes-1] == 238
    view[bytes-1] = 239
  var storage = takeResident(owner)
  assert borrowRW(owner).len == 0
  assert storage.logicalBytes == uint64(bytes)
  let backing = storage.mappedBytes
  assert backing >= uint64(bytes)
  let held = residentWitnessSnapshot()
  assert held.acquisitions == before.acquisitions+1 and held.releases == before.releases
  assert held.logicalBytes == before.logicalBytes+uint64(bytes)
  assert held.mappedBytes == before.mappedBytes+backing
  var cell: nil StorageCell = StorageCell(storage: move(storage))
  assert cell != nil and storage.len == 0
  if cell != nil:
    # A real owning heap child remains live after its source variable is disarmed.
    assert residentWitnessSnapshot() == held
    var recovered = move(cell.storage)
    cell = nil
    assert residentWitnessSnapshot() == held
    assert recovered.logicalBytes == uint64(bytes) and recovered.mappedBytes == backing
    block:
      # Final storage still holds the original mutations and untouched zero bytes.
      let view = borrowRW(recovered)
      assert view.len == bytes
      for index in 0..<view.len:
        let expected = if index == 0: 7'u8
          elif index == 4095: 149'u8
          elif index == bytes-1: 239'u8
          else: 0'u8
        assert view[index] == expected
    # The recovered owner drops here; default aggregate destruction delegates the actual storage child.

proc checkHeapDrop() =
  ## Retiring the final managed reference must release its still-populated foreign child exactly once.
  let before = residentWitnessSnapshot()
  var allocation = tryMapFreshZero(4097)
  assert allocation.error == ResidentAllocationError.None
  var owner = takeOwned(allocation)
  var storage = takeResident(owner)
  var cell: nil StorageCell = StorageCell(storage: move(storage))
  assert cell != nil
  cell = nil
  let after = residentWitnessSnapshot()
  assert after.acquisitions == before.acquisitions+1
  assert after.releases == before.releases+1
  assert after.logicalBytes == before.logicalBytes and after.mappedBytes == before.mappedBytes

proc checkMoveOverwrite() =
  ## Legal replacement retires an already populated destination while preserving the arriving mapping.
  let before = residentWitnessSnapshot()
  block:
    var oldAllocation = tryMapFreshZero(4099)
    assert oldAllocation.error == ResidentAllocationError.None
    var oldOwner = takeOwned(oldAllocation)
    var destination = takeResident(oldOwner)
    block:
      # Distinct first/last markers identify the mapping that must be retired by replacement.
      var view = borrowRW(destination)
      view[0] = 19
      view[4098] = 31
    var newAllocation = tryMapFreshZero(8197)
    assert newAllocation.error == ResidentAllocationError.None
    var newOwner = takeOwned(newAllocation)
    var source = takeResident(newOwner)
    let arrivingBacking = source.mappedBytes
    block:
      # These independent markers must survive the legal move into the live destination.
      var view = borrowRW(source)
      view[0] = 211
      view[8196] = 233
    let both = residentWitnessSnapshot()
    assert both.acquisitions == before.acquisitions+2 and both.releases == before.releases
    destination = move(source)
    assert source.len == 0 and source.logicalBytes == 0 and source.mappedBytes == 0
    let replaced = residentWitnessSnapshot()
    assert replaced.acquisitions == both.acquisitions and replaced.releases == before.releases+1
    assert replaced.logicalBytes == before.logicalBytes+8197
    assert replaced.mappedBytes == before.mappedBytes+arrivingBacking
    assert destination.logicalBytes == 8197 and destination.mappedBytes == arrivingBacking
    block:
      # The surviving extent and bytes come from the arriving owner, with no stale first mapping view.
      let view = borrowRW(destination)
      assert view.len == 8197 and view[0] == 211 and view[8196] == 233
      for index in 1..<8196:
        assert view[index] == 0
  let after = residentWitnessSnapshot()
  assert after.acquisitions == before.acquisitions+2 and after.releases == before.releases+2
  assert after.logicalBytes == before.logicalBytes and after.mappedBytes == before.mappedBytes

proc checkRefusal() =
  ## Inject exactly one selected-allocation refusal; no owner, extent or later request is lost.
  let before = residentWitnessSnapshot()
  refuseNextResidentAllocation()
  let refused = tryMapFreshZero(4099)
  assert refused.error == ResidentAllocationError.AllocationRefused
  let after = residentWitnessSnapshot()
  assert after.refusals == before.refusals+1
  assert after.acquisitions == before.acquisitions and after.releases == before.releases
  assert after.logicalBytes == before.logicalBytes and after.mappedBytes == before.mappedBytes
  foreignCycle(4099)

checkDefaults()
checkManaged()
when FreshRWProfileEnabled:
  # These are actual layout requirements, not a cast to a managed seq representation.
  let layout = residentWitnessLayout()
  assert layout[0] == 24 and layout[1] == 16
  assert layout[3] == 8 and layout[4] == 16 and layout[5] == 0 and layout[6] == 8
  checkRefusal()
  checkHeapDrop()
  checkMoveOverwrite()
  foreignCycle(1048579)
  # Warm the real heap-owner path before the fresh1000-cycle ARC/lifetime observation.
  foreignCycle(4099)
  let occupiedBefore = getOccupiedMem()
  let foreignBefore = residentWitnessSnapshot()
  for cycle in 0..<1000:
    foreignCycle(4099)
    let occupiedNow = getOccupiedMem()
    assert occupiedNow == occupiedBefore, "resident ARC growth during repeated final releases"
  let occupiedAfter = getOccupiedMem()
  let foreignAfter = residentWitnessSnapshot()
  assert occupiedAfter == occupiedBefore
  assert foreignAfter.acquisitions == foreignBefore.acquisitions+1000
  assert foreignAfter.releases == foreignBefore.releases+1000
  assert foreignAfter.logicalBytes == foreignBefore.logicalBytes
  assert foreignAfter.mappedBytes == foreignBefore.mappedBytes
  recordArcRelease("pvm_resident_bytes", 1000, occupiedBefore, occupiedAfter)
else:
  # Compatibility profiles preserve the managed route and never bind foreign OS routines.
  let occupiedBefore = getOccupiedMem()
  for cycle in 0..<1000: checkManaged()
  let occupiedAfter = getOccupiedMem()
  assert occupiedAfter == occupiedBefore
  assert residentWitnessSnapshot() == default(ResidentWitnessSnapshot)
  recordArcRelease("pvm_resident_bytes", 1000, occupiedBefore, occupiedAfter)

echo "pvm resident bytes ok"
