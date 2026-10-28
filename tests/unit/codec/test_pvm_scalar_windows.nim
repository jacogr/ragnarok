# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded scalar windows preserve checked access, immutable epochs and shared writer identity.
# @@Verification={"arc": "pvm_scalar_windows_arc_release"}
import std/assertions
import std/syncio
import ../../../src/pvm/machine as pvm_machine
import ../../support/testing_arc_evidence

proc sameMemory(left, right: Memory) =
  ## Every initialized byte and permission participates, including unchanged and inaccessible pages.
  for index in [16'u32, 17'u32, 1048575'u32]:
    let a = pageImage(left, PageIndex(index)).value
    let b = pageImage(right, PageIndex(index)).value
    assert a.access == b.access
    for offset in 0..<4096: assert a.bytes[offset] == b.bytes[offset]

proc cycle(mode: int) =
  ## Successful caches must not change invalid-width, fault ordering, endpoint or alias semantics.
  var images = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte])),
    PageImage(index: PageIndex(17), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte])),
    PageImage(index: PageIndex(1048575), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))]
  if mode == 1: images[0].access = PageAccess.ReadOnly
  if mode == 2:
    images[0].access = PageAccess.ReadOnly
    images[1].access = PageAccess.Inaccessible
  if mode == 3: images[2].access = PageAccess.Inaccessible
  for side in 0..<3:
    # Nonuniform source bytes expose stale chunk selection and neighboring-byte mutation.
    for offset in 0..<4096: images[side].bytes[offset] = byte((offset*37+side*53) and 255)
  let source = captureMemory(images, PageLimit(3)).value
  var expected = source
  let writer = newScalarMemoryWriter(source).value
  let alias = writer
  var frozen: seq[Memory] = @[]
  var oracle: seq[Memory] = @[]
  for operation in 0..<2000:
    # Repeated hot accesses alternate with chunk/page edges, missing pages and wrapped physical addresses.
    let offsets = [0'u64, 0, 0, 0, 504, 505, 506, 507, 508, 509, 510, 511,
      512, 513, 4090, 4091, 4092, 4093, 4094, 4095, 4096, 4097, 8191,
      0xffff0000'u64, 0xfffefff8'u64, 0xfffefff9'u64, 0xfffeffff'u64,
      0x100000000'u64, 0x100000001'u64]
    let widths = [1'u8, 2, 4, 8, 0, 3, 16, 8, 4, 2, 1]
    let address = MemoryAddress(65536'u64+offsets[(operation div 11) mod offsets.len])
    let width = AccessWidth(widths[operation mod widths.len])
    let before = load(expected, address, width)
    let actual = load(alias, address, width)
    assert actual.error == before.error
    if before.error == MachineError.None:
      assert uint64(actual.value) == uint64(before.value)
    elif before.error == MachineError.Fault:
      assert uint32(actual.faultPage) == uint32(before.faultPage)
    let value = RegisterValue(uint64(operation)*0x123456789abcdef'u64)
    let changed = store(expected, address, width, value)
    let done = store(writer, address, width, value)
    assert done.error == changed.error
    if changed.error == MachineError.None:
      expected = changed.value
    elif changed.error == MachineError.Fault:
      assert uint32(done.faultPage) == uint32(changed.faultPage)
    let after = load(expected, address, width)
    let reread = load(alias, address, width)
    assert after.error == reread.error
    if after.error == MachineError.None:
      assert uint64(after.value) == uint64(reread.value)
    if operation mod 37 == 0:
      # Seal through an alias, then continue accessing the same writer identity in the next epoch.
      let sealed = snapshotMemory(alias).value
      sameMemory(sealed, expected)
      frozen.add(sealed)
      oracle.add(expected)
  sameMemory(snapshotMemory(writer).value, expected)
  for epoch in 0..<frozen.len:
    # Every historical snapshot remains immutable after all later cached writes.
    sameMemory(frozen[epoch], oracle[epoch])
  for side in 0..<3:
    let original = pageImage(source, images[side].index).value
    assert original.access == images[side].access
    for offset in 0..<4096: assert original.bytes[offset] == images[side].bytes[offset]

proc sparseSlotCycle() =
  ## Exact sparse page identities must survive positive-hint collisions, failed permissions and alias epoch transitions.
  var images: seq[PageImage] = @[]
  for index in 0..<15:
    # Stride65536 page ordinals collides in both64/256-slot hint tables while staying inside the physical page domain.
    var image = PageImage(index: PageIndex(uint32(16+index*65536)),
      access: PageAccess.ReadWrite, bytes: default(array[4096, byte]))
    if index mod 3 == 1: image.access = PageAccess.ReadOnly
    if index mod 3 == 2: image.access = PageAccess.Inaccessible
    for offset in 0..<4096: image.bytes[offset] = byte((index*43+offset*19) and 255)
    images.add(image)
  images.add(PageImage(index: PageIndex(1048575), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte])))
  let source = captureMemory(images, PageLimit(uint32(images.len))).value
  let writer = newScalarMemoryWriter(source).value
  let alias = writer
  var expected = source
  var frozen: seq[Memory] = @[]
  var oracle: seq[Memory] = @[]
  for epoch in 0..<3:
    for operation in 0..<144:
      # Repeated nonadjacent pages defeat recent hints; crossing/missing/final-page cases preserve original fault precedence.
      let index = (operation*7) mod images.len
      let offsets = [0'u64, 505, 511, 4090, 4095, 4096, 0, 4095, 1]
      let widths = [1'u8, 2, 4, 8, 0, 3, 8]
      let physical = uint64(uint32(images[index].index))*4096+offsets[operation mod offsets.len]
      let address = MemoryAddress(physical+(if operation mod 2 == 0: 0x100000000'u64 else: 0'u64))
      let width = AccessWidth(widths[operation mod widths.len])
      let wanted = load(expected, address, width)
      let actual = load(alias, address, width)
      assert actual.error == wanted.error
      if wanted.error == MachineError.None: assert actual.value == wanted.value
      elif wanted.error == MachineError.Fault: assert actual.faultPage == wanted.faultPage
      let value = RegisterValue(uint64(operation+epoch*1000))
      let updated = store(expected, address, width, value)
      let written = store(writer, address, width, value)
      assert written.error == updated.error
      if updated.error == MachineError.None: expected = updated.value
      elif updated.error == MachineError.Fault: assert written.faultPage == updated.faultPage
    let sealed = snapshotMemory(alias).value
    frozen.add(sealed)
    oracle.add(expected)
  for epoch in 0..<frozen.len:
    for index in 0..<images.len:
      # Full historical byte/permission comparisons reject stale header/chunk capabilities after subsequent writes.
      let actual = pageImage(frozen[epoch], images[index].index).value
      let wanted = pageImage(oracle[epoch], images[index].index).value
      assert actual.access == wanted.access
      for offset in 0..<4096: assert actual.bytes[offset] == wanted.bytes[offset]
  for index in 0..<images.len:
    let original = pageImage(source, images[index].index).value
    assert original.access == images[index].access
    for offset in 0..<4096: assert original.bytes[offset] == images[index].bytes[offset]

proc chunkEpochCycle() =
  ## Unknown chunk bits must never reuse shared payloads, including spare-window hits and two-chunk stores.
  var images: seq[PageImage] = @[]
  for index in 0..<3:
    var image = PageImage(index: PageIndex(uint32(16+index)), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))
    for offset in 0..<4096: image.bytes[offset] = byte((index*31+offset*13) and 255)
    images.add(image)
  let source = captureMemory(images, PageLimit(3)).value
  let writer = newScalarMemoryWriter(source).value
  let alias = writer
  var expected = source
  var frozen: seq[Memory] = @[]
  var oracle: seq[Memory] = @[]
  for epoch in 0..<3:
    for chunk in 0..<8:
      for turn in 0..<9:
        # Three pages rotate primary/spare windows; accesses straddling512-byte boundaries require both private chunks first.
        let index = (turn*2) mod 3
        let offsets = [3, 505, 511]
        let address = MemoryAddress(uint64(16+index)*4096+uint64(chunk*512+offsets[turn mod 3]))
        let width = AccessWidth([1'u8, 2, 4, 8][turn mod 4])
        let prior = load(alias, address, width)
        let wantedPrior = load(expected, address, width)
        assert prior.error == wantedPrior.error
        if prior.error == MachineError.None: assert prior.value == wantedPrior.value
        elif prior.error == MachineError.Fault: assert prior.faultPage == wantedPrior.faultPage
        let value = RegisterValue(uint64(epoch*1000+chunk*37+turn+7))
        let wanted = store(expected, address, width, value)
        let actual = store(writer, address, width, value)
        assert actual.error == wanted.error
        if wanted.error == MachineError.None: expected = wanted.value
        elif wanted.error == MachineError.Fault: assert actual.faultPage == wanted.faultPage
    frozen.add(snapshotMemory(alias).value)
    oracle.add(expected)
  for epoch in 0..<frozen.len:
    for index in 0..<images.len:
      # Full historical images remain independent after later writes reuse every chunk and window through the alias.
      let actual = pageImage(frozen[epoch], images[index].index).value
      let wanted = pageImage(oracle[epoch], images[index].index).value
      assert actual.access == wanted.access
      for offset in 0..<4096: assert actual.bytes[offset] == wanted.bytes[offset]
  for index in 0..<images.len:
    let original = pageImage(source, images[index].index).value
    assert original.access == images[index].access
    for offset in 0..<4096: assert original.bytes[offset] == images[index].bytes[offset]

proc workingSetCycle() =
  ## Alternate two writable pages and a read-only table, then evict both writable owners and seal through aliases.
  var images = [PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte])),
    PageImage(index: PageIndex(48), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte])),
    PageImage(index: PageIndex(49), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte])),
    PageImage(index: PageIndex(50), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte])),
    PageImage(index: PageIndex(1048543), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))]
  for page in 0..<images.len:
    # Full-page expectations distinguish stale cached owners from the current epoch and neighboring pages.
    for offset in 0..<4096: images[page].bytes[offset] = byte((offset*19+page*43) and 255)
  let source = captureMemory(images, PageLimit(5)).value
  let writer = newScalarMemoryWriter(source).value
  let alias = writer
  let unchanged = snapshotMemory(alias).value
  var expected = source
  var frozen: seq[Memory] = @[]
  var oracle: seq[Memory] = @[]
  for epoch in 0..<3:
    for turn in 0..<24:
      # Consecutive state/stack accesses use both writable windows; extra pages force bounded eviction.
      let pages = [48'u64, 1048543, 48, 1048543, 49, 50, 48, 1048543]
      let page = pages[turn mod pages.len]
      let offset = [3'u64, 507, 511, 512, 1021, 2047, 3583, 4088][turn mod 8]
      let address = MemoryAddress(page*4096+offset)
      let original = load(expected, address, AccessWidth(8)).value
      assert uint64(load(alias, address, AccessWidth(8)).value) == uint64(original)
      let value = RegisterValue(uint64(epoch*100+turn+1)*0x0102030405060708'u64)
      assert store(writer, address, AccessWidth(8), value).value
      expected = store(expected, address, AccessWidth(8), value).value
      assert uint64(load(alias, address, AccessWidth(8)).value) == uint64(value)
      let table = MemoryAddress(65536+uint64((turn mod 16)*8))
      assert uint64(load(alias, table, AccessWidth(8)).value) ==
          uint64(load(source, table, AccessWidth(8)).value)
      assert store(writer, table, AccessWidth(8), RegisterValue(0)).error == MachineError.Fault
    frozen.add(snapshotMemory(alias).value)
    oracle.add(expected)
  for page in 0..<images.len:
    # Immutable epochs and the source retain every byte after cached writes through the same alias.
    let original = pageImage(source, images[page].index).value
    let sealed = pageImage(unchanged, images[page].index).value
    assert original.access == images[page].access and sealed.access == images[page].access
    for offset in 0..<4096:
      assert original.bytes[offset] == images[page].bytes[offset]
      assert sealed.bytes[offset] == images[page].bytes[offset]
    for epoch in 0..<frozen.len:
      let actual = pageImage(frozen[epoch], images[page].index).value
      let wanted = pageImage(oracle[epoch], images[page].index).value
      assert actual.access == wanted.access
      for offset in 0..<4096: assert actual.bytes[offset] == wanted.bytes[offset]

proc fixedWidthCycle[Width: static[int]]() =
  ## Fixed-width entry points preserve immutable/runtime results, endpoint precedence, COW epochs and nil refusal.
  let invalid: nil ScalarMemoryWriter = nil
  assert load[Width](invalid, MemoryAddress(0)).error == MachineError.InvalidOwner
  assert store[Width](invalid, MemoryAddress(0), RegisterValue(0)).error ==
      MachineError.InvalidOwner
  var images = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte])),
    PageImage(index: PageIndex(17), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte])),
    PageImage(index: PageIndex(1048575), access: PageAccess.ReadWrite,
      bytes: default(array[4096, byte]))]
  for page in 0..<images.len:
    # Nonuniform source patterns expose extension, address wrapping and adjacent-byte clobbering.
    for offset in 0..<4096: images[page].bytes[offset] = byte((offset*29+page*41) and 255)
  let source = captureMemory(images, PageLimit(3)).value
  let writer = newScalarMemoryWriter(source).value
  let alias = writer
  var expected = source
  var frozen: seq[Memory] = @[]
  var oracle: seq[Memory] = @[]
  for epoch in 0..<3:
    for address in [0'u64, 65535, 65536, 65537, 66040, 66041, 66043, 66046, 66047,
        66048, 69624, 69625, 69628, 69631, 69632, 73727, 73728, 0xfffffff7'u64,
        0xfffffff8'u64, 0xfffffffb'u64, 0xfffffffe'u64, 0xffffffff'u64,
        0x100010000'u64, high(uint64)]:
      # Complete checked preflight still precedes mutation at chunk/page/physical endpoints and protected addresses.
      let at = MemoryAddress(address)
      let width = AccessWidth(byte(Width))
      let before = load(expected, at, width)
      let actual = load[Width](alias, at)
      assert actual.error == before.error
      if before.error == MachineError.None: assert uint64(actual.value) == uint64(before.value)
      elif before.error == MachineError.Fault: assert uint32(actual.faultPage) == uint32(
          before.faultPage)
      let value = RegisterValue(address xor (uint64(epoch+1)*0x1122334455667788'u64))
      let changed = store(expected, at, width, value)
      let done = store[Width](writer, at, value)
      assert done.error == changed.error
      if changed.error == MachineError.None: expected = changed.value
      elif changed.error == MachineError.Fault: assert uint32(done.faultPage) == uint32(
          changed.faultPage)
      let after = load(expected, at, width)
      let observed = load[Width](alias, at)
      assert observed.error == after.error
      if after.error == MachineError.None: assert uint64(observed.value) == uint64(after.value)
      elif after.error == MachineError.Fault: assert uint32(observed.faultPage) == uint32(
          after.faultPage)
    frozen.add(snapshotMemory(alias).value)
    oracle.add(expected)
  for epoch in 0..<frozen.len:
    # Every byte and permission remains stable in historical epochs after later writes through an alias.
    sameMemory(frozen[epoch], oracle[epoch])
  for page in 0..<images.len:
    let original = pageImage(source, images[page].index).value
    assert original.access == images[page].access and original.bytes == images[page].bytes

fixedWidthCycle[1]()
fixedWidthCycle[2]()
fixedWidthCycle[4]()
fixedWidthCycle[8]()

# Differential sweeps exercise all widths, chunk/page edges, protected/wrapped addresses and failed writes.
for mode in 0..<4: cycle(mode)
for repeat in 0..<20:
  for mode in 0..<4: cycle(mode)
workingSetCycle()
sparseSlotCycle() # Independent sparse collision and immutable-epoch witness before retained-heap accounting.

chunkEpochCycle() # Independent first-touch/cross-chunk/epoch witness precedes retained-heap accounting.
let before = getOccupiedMem()
for repeat in 0..<1000:
  workingSetCycle() # All retained readable/private page owners retire without cycles or published mutation.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_scalar_windows", 1000, before, after)
echo "PVM scalar page windows passed"
echo "ARC_RELEASE cycles=1000 unchanged"
