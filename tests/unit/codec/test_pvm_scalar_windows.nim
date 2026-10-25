# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded scalar windows preserve checked access, immutable epochs and shared writer identity.
# @@Verification={"arc": "pvm_scalar_windows_arc_release"}
import std/[assertions, syncio]
import ../../../src/pvm/machine
import ../../support/arc_evidence

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

# Differential sweeps exercise all widths, chunk/page edges, protected/wrapped addresses and failed writes.
for mode in 0..<4: cycle(mode)
for repeat in 0..<20:
  for mode in 0..<4: cycle(mode)
workingSetCycle()
let before = getOccupiedMem()
for repeat in 0..<1000:
  workingSetCycle() # All retained readable/private page owners retire without cycles or published mutation.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_scalar_windows", 1000, before, after)
echo "PVM scalar page windows passed"
echo "ARC_RELEASE cycles=1000 unchanged"
