# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete page images cover immutable append boundaries, access, limits and history.

import std/[assertions, syncio]
import ../../../src/pvm/machine

proc baseImages(count: int): seq[PageImage] =
  ## Sparse nonzero pages distinguish sorted slots, physical ordinals, permissions and chunk boundaries.
  result = @[]
  for slot in 0..<count:
    # Alternating access includes retained inaccessible bytes that an append must never erase.
    let access = if slot mod 3 == 0: PageAccess.ReadWrite
      elif slot mod 3 == 1: PageAccess.ReadOnly else: PageAccess.Inaccessible
    var page = PageImage(index: PageIndex(uint32(16+slot*2)), access: access,
      bytes: default(array[4096, byte]))
    for offset in 0..<4096:
      # This independent full-image pattern includes page ends and every 512-byte chunk boundary.
      page.bytes[offset] = byte((slot*11+offset*3+7) mod 251)
    result.add(page)

proc expectedImages(prefix: openArray[PageImage], first, count: int,
    access: PageAccess): seq[PageImage] =
  ## Construct expected values directly; no production mapping helper supplies the oracle.
  result = @[]
  for page in prefix:
    # PageImage is a copied fixed array, never an alias of a published page or mutable input seq.
    result.add(page)
  for offset in 0..<count:
    # All absent appended pages start zero, independently of requested retained access.
    result.add(PageImage(index: PageIndex(uint32(first+offset)), access: access,
      bytes: default(array[4096, byte])))

proc checkImages(memory: Memory, expected: openArray[PageImage]) =
  ## Check every sorted mapping, permission and byte, including inaccessible retained images.
  let layout = memoryLayout(memory).value
  assert layout.len == expected.len and uint32(memoryPageCount(memory).value) == uint32(expected.len)
  for slot in 0..<expected.len:
    # Metadata checks distinguish an absent zero page from materialized inaccessible zero storage.
    assert layout[slot].index == expected[slot].index and layout[slot].access == expected[slot].access
    assert pageImage(memory, expected[slot].index).value == expected[slot]

proc boundaries() =
  ## Exact fills and cross-block tails preserve sparse outside pages and independent sibling owners.
  for sample in [(0, 1), (63, 1), (64, 1), (64, 64), (65, 63), (127, 2), (128, 65)]:
    # Each pair exercises a distinct empty/full/partial boundary without a redundant Cartesian matrix.
    let count = sample[0]
    let added = sample[1]
    let images = baseImages(count)
    let base = captureMemory(images, PageLimit(uint32(count+added))).value
    let left = withPageRange(base, PageIndex(4096), PageIndex(uint32(4096+added)),
      PageAccess.ReadWrite, PageContent.Zeroed).value
    let right = withPageRange(base, PageIndex(4096), PageIndex(uint32(4096+added)),
      PageAccess.ReadWrite, PageContent.Preserved).value
    let expected = expectedImages(images, 4096, added, PageAccess.ReadWrite)
    checkImages(left, expected)
    checkImages(right, expected)
    checkImages(base, images)
    for page in images:
      # Public page identity proves unchanged page ownership, not internal PageBlock sharing.
      assert samePage(base, left, page.index) and samePage(base, right, page.index)
    let written = store(left, MemoryAddress(4096'u64*4096+511), AccessWidth(2),
      RegisterValue(0xabcd)).value
    var changed = expectedImages(images, 4096, added, PageAccess.ReadWrite)
    changed[count].bytes[511] = 0xcd
    changed[count].bytes[512] = 0xab
    checkImages(written, changed)
    let remapped = withPageRange(written, PageIndex(4096), PageIndex(4097),
      PageAccess.ReadOnly, PageContent.Preserved).value
    changed[count].access = PageAccess.ReadOnly
    checkImages(remapped, changed)
    checkImages(left, expected)
    checkImages(right, expected)
    checkImages(base, images)
    if count != 0:
      # A prefix write followed by a remap cannot mutate a shared complete block or either sibling.
      let prefixWrite = store(right, MemoryAddress(65536), AccessWidth(1), RegisterValue(239)).value
      let prefixMap = withPageRange(prefixWrite, PageIndex(16), PageIndex(17),
        PageAccess.ReadOnly, PageContent.Preserved).value
      var prefixExpected = expectedImages(images, 4096, added, PageAccess.ReadWrite)
      prefixExpected[0].bytes[0] = 239
      prefixExpected[0].access = PageAccess.ReadOnly
      checkImages(prefixMap, prefixExpected)
      checkImages(base, images)
      checkImages(left, expected)
      checkImages(right, expected)

proc accessAndFallback() =
  ## All access/content pairs distinguish retained inaccessible zeros from dropped sparse storage.
  let images = baseImages(65)
  let base = captureMemory(images, PageLimit(67)).value
  for access in [PageAccess.Inaccessible, PageAccess.ReadOnly, PageAccess.ReadWrite]:
    # Permission results are independent of whether absent pages were requested preserved or zeroed.
    for content in [PageContent.Preserved, PageContent.Zeroed]:
      let dropped = access == PageAccess.Inaccessible and content == PageContent.Zeroed
      let count = if dropped: 0 else: 2
      let mapped = withPageRange(base, PageIndex(4096), PageIndex(4098), access, content).value
      checkImages(mapped, expectedImages(images, 4096, count, access))
      let loaded = load(mapped, MemoryAddress(4096'u64*4096), AccessWidth(1))
      let written = store(mapped, MemoryAddress(4096'u64*4096), AccessWidth(1), RegisterValue(91))
      if access == PageAccess.Inaccessible:
        # Both absent and retained inaccessible pages fault, but their materialized counts differ.
        assert loaded.error == MachineError.Fault and written.error == MachineError.Fault
      else:
        # Read-only zeros remain readable while only writable pages admit a private successor.
        assert loaded.error == MachineError.None and uint64(loaded.value) == 0
        if access == PageAccess.ReadOnly:
          assert written.error == MachineError.Fault
        else:
          assert written.error == MachineError.None
          assert uint64(load(written.value, MemoryAddress(4096'u64*4096), AccessWidth(1)).value) == 91
      checkImages(base, images)
      checkImages(mapped, expectedImages(images, 4096, count, access))
  # A tail overlap has stop == len but start != len: it must still zero the old final page.
  let overlap = withPageRange(base, PageIndex(144), PageIndex(146), PageAccess.ReadOnly,
    PageContent.Zeroed).value
  var expected: seq[PageImage] = @[]
  for slot in 0..<64:
    expected.add(images[slot]) # Every preceding sparse page retains its exact nonzero image.
  for ordinal in [144'u32, 145]:
    expected.add(PageImage(index: PageIndex(ordinal), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte])))
  checkImages(overlap, expected)
  checkImages(base, images)

proc admission() =
  ## Combined refusals retain precedence, and inaccessible materialization consumes the original policy.
  let images = baseImages(64)
  let full = captureMemory(images, PageLimit(64)).value
  assert withPageRange(default(Memory), PageIndex(2), PageIndex(1), PageAccess.ReadOnly,
    PageContent.Zeroed).error == MachineError.InvalidOwner
  assert withPageRange(full, PageIndex(0), PageIndex(0x100001), PageAccess.ReadOnly,
    PageContent.Zeroed).error == MachineError.InvalidRange
  assert withPageRange(full, PageIndex(4096), PageIndex(4097), PageAccess.Inaccessible,
    PageContent.Preserved).error == MachineError.LimitExceeded
  checkImages(withPageRange(full, PageIndex(0x100000), PageIndex(0x100000),
    PageAccess.ReadOnly, PageContent.Zeroed).value, images)
  let room = captureMemory(images, PageLimit(65)).value
  checkImages(withPageRange(room, PageIndex(4096), PageIndex(4097), PageAccess.Inaccessible,
    PageContent.Preserved).value, expectedImages(images, 4096, 1, PageAccess.Inaccessible))
  let empty = captureMemory([], PageLimit(0)).value
  assert withPageRange(empty, PageIndex(4096), PageIndex(4097), PageAccess.Inaccessible,
    PageContent.Preserved).error == MachineError.LimitExceeded
  checkImages(withPageRange(empty, PageIndex(4096), PageIndex(4097), PageAccess.Inaccessible,
    PageContent.Zeroed).value, [])
  let last = captureMemory([], PageLimit(1)).value
  checkImages(withPageRange(last, PageIndex(0xfffff), PageIndex(0x100000), PageAccess.ReadOnly,
    PageContent.Preserved).value, [PageImage(index: PageIndex(0xfffff), access: PageAccess.ReadOnly,
    bytes: default(array[4096, byte]))])
  checkImages(full, images)

boundaries()
accessAndFallback()
admission()
echo "PVM immutable page-range append passed"
