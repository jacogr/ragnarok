# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The slot-only memory delta validates an entire map before exposing sorted copied positions.

import std/[assertions, syncio]
import ../../../src/pvm/machine

proc checked[T](r: MachineResult[T]): T =
  ## Extract only a successful independent snapshot or slot vector.
  assert r.error == MachineError.None
  r.value

proc image(ordinal: uint32, marker: byte = 0): PageImage =
  ## Use sparse physical ordinals so a returned slot cannot be mistaken for a page index.
  result = PageImage(index: PageIndex(16'u32+ordinal*2), access: PageAccess.ReadWrite)
  result.bytes[0] = marker

proc changedImage(source: PageImage, marker: byte): PageImage =
  ## Keep the map stable while giving a replacement page independently observable bytes.
  result = source
  result.bytes[0] = marker

block invalidAndEmptyOwners:
  ## Default handles refuse even when paired with a valid empty owner; valid empties have no slots.
  let empty = checked(captureMemory([], PageLimit(0)))
  assert changedMemoryPageSlots(default(Memory), empty).error == MachineError.InvalidOwner
  assert changedMemoryPageSlots(empty, default(Memory)).error == MachineError.InvalidOwner
  assert checked(changedMemoryPageSlots(empty, empty)).len == 0
  let anotherEmpty = checked(captureMemory([], PageLimit(0)))
  assert checked(changedMemoryPageSlots(empty, anotherEmpty)).len == 0

var images: seq[PageImage] = @[]
for ordinal in 0'u32..<131'u32:
  # Two full directory blocks and a three-page tail exercise both block and last-page bounds.
  images.add(image(ordinal))
let baseline = checked(captureMemory(images, PageLimit(131)))

block unchangedAndSharedBlocks:
  ## Same-owner and unchanged immutable blocks return no changes; equal bytes in a new page owner still count.
  assert checked(changedMemoryPageSlots(baseline, baseline)).len == 0
  let one = checked(withReplacedPages(baseline, [images[64]]))
  assert checked(changedMemoryPageSlots(baseline, one)) == @[MemoryPageSlot(64)]
  assert checked(changedMemoryPageSlots(one, baseline)) == @[MemoryPageSlot(64)]

block sparseAcrossBlocksAndTail:
  ## The unchanged middle block is shared; slot 130 is inside the partial final block.
  let replacements = [changedImage(images[1], 11), changedImage(images[130], 22)]
  let after = checked(withReplacedPages(baseline, replacements))
  let slots = checked(changedMemoryPageSlots(baseline, after))
  assert slots == @[MemoryPageSlot(1), MemoryPageSlot(130)]
  var copied = default(array[4096, byte])
  let description = checked(copyMemoryPage(after, slots[1], copied))
  assert description.index == images[130].index and copied[0] == 22

block denseAndSorted:
  ## More than one block changes, including multiple slots per block and the last tail slot.
  var replacements: seq[PageImage] = @[]
  var expected: seq[MemoryPageSlot] = @[]
  for slot in 0..<131:
    if slot mod 3 == 0:
      replacements.add(changedImage(images[slot], byte(slot mod 251+1)))
      expected.add(MemoryPageSlot(uint32(slot)))
  let after = checked(withReplacedPages(baseline, replacements))
  assert checked(changedMemoryPageSlots(baseline, after)) == expected

block refuseAfterEarlierByteChange:
  ## A later access or physical-index mismatch must discard the earlier valid byte delta.
  let byteChange = checked(withReplacedPages(baseline, [changedImage(images[1], 99)]))
  var alteredAccess = images[130]
  alteredAccess.access = PageAccess.ReadOnly
  let accessMismatch = checked(withPage(byteChange, alteredAccess))
  assert changedMemoryPageSlots(baseline, accessMismatch).error == MachineError.InvalidRange
  var shifted = images
  shifted[130].index = PageIndex(uint32(shifted[130].index)+1)
  let indexMismatch = checked(captureMemory(shifted, PageLimit(131)))
  assert changedMemoryPageSlots(byteChange, indexMismatch).error == MachineError.InvalidRange
  let shorter = checked(captureMemory(images.toOpenArray(0, 129), PageLimit(130)))
  assert changedMemoryPageSlots(baseline, shorter).error == MachineError.InvalidRange

block ownedContiguousRegions:
  ## Each successful copy owns every byte independently of input, source and other returned regions.
  var input = default(array[3, PageImage])
  for page in 0..<input.len:
    # A dense nonzero pattern exercises the unknown-proof path and the last admitted slot.
    input[page] = PageImage(index: PageIndex(uint32(16+page)), access: PageAccess.ReadWrite)
    for offset in 0..<4096: input[page].bytes[offset] = byte((page*29+offset*7) mod 251+1)
  var source = checked(captureMemory(input, PageLimit(3)))
  let description = PageDescription(index: PageIndex(16), access: PageAccess.ReadWrite)
  var created = copyMemoryRegion(source, MemoryPageSlot(0), PageCount(3), description)
  assert created.error == MachineError.None
  var first = takeValue(created)
  assert created.error == MachineError.Uninitialized and first.len == 3*4096
  let second = checked(copyMemoryRegion(source, MemoryPageSlot(0), PageCount(3), description))
  let last = checked(copyMemoryRegion(source, MemoryPageSlot(2), PageCount(1),
    PageDescription(index: PageIndex(18), access: PageAccess.ReadWrite)))
  input[0].bytes[0] = 0 # Caller input storage was captured, never borrowed by the source or copies.
  first[0] = 0
  assert checked(pageImage(source, PageIndex(16))).bytes[0] == 1
  assert second[0] == 1
  let readonly = checked(withPageRange(source, PageIndex(16), PageIndex(19),
    PageAccess.ReadOnly, PageContent.Preserved))
  let readCopy = checked(copyMemoryRegion(readonly, MemoryPageSlot(0), PageCount(3),
    PageDescription(index: PageIndex(16), access: PageAccess.ReadOnly)))
  source = default(Memory) # The copied payloads remain owned after this source handle retires.
  for page in 0..<3:
    for offset in 0..<4096:
      # The authored pattern also checks that no nonfirst page or byte suffix is omitted.
      let expected = byte((page*29+offset*7) mod 251+1)
      let at = page*4096+offset
      assert first[at] == (if at == 0: 0'u8 else: expected)
      assert second[at] == expected and readCopy[at] == expected
      if page == 2: assert last[offset] == expected

block regionRefusals:
  ## Refuse the complete requested capability before exposing any valid earlier-page prefix.
  let description = PageDescription(index: PageIndex(16), access: PageAccess.ReadWrite)
  let empty = checked(captureMemory([], PageLimit(0)))
  assert copyMemoryRegion(default(Memory), MemoryPageSlot(0), PageCount(0),
    description).error == MachineError.InvalidOwner
  assert copyMemoryRegion(empty, MemoryPageSlot(0), PageCount(0),
    description).error == MachineError.InvalidRange
  var input = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(17), access: PageAccess.ReadWrite),
    PageImage(index: PageIndex(18), access: PageAccess.ReadWrite)]
  let source = checked(captureMemory(input, PageLimit(3)))
  assert copyMemoryRegion(source, MemoryPageSlot(0), PageCount(0),
    description).error == MachineError.InvalidRange
  assert copyMemoryRegion(source, MemoryPageSlot(3), PageCount(1),
    description).error == MachineError.InvalidRange
  assert copyMemoryRegion(source, MemoryPageSlot(high(uint32)), PageCount(1),
    description).error == MachineError.InvalidRange
  assert copyMemoryRegion(source, MemoryPageSlot(1), PageCount(high(uint32)),
    description).error == MachineError.InvalidRange
  assert copyMemoryRegion(source, MemoryPageSlot(0), PageCount(3), PageDescription(
    index: PageIndex(high(uint32)), access: PageAccess.ReadWrite)).error ==
    MachineError.InvalidRange
  assert copyMemoryRegion(source, MemoryPageSlot(0), PageCount(3), PageDescription(
    index: PageIndex(0xfffff), access: PageAccess.ReadWrite)).error == MachineError.InvalidRange
  assert copyMemoryRegion(source, MemoryPageSlot(0), PageCount(3), PageDescription(
    index: PageIndex(17), access: PageAccess.ReadWrite)).error == MachineError.InvalidRange
  assert copyMemoryRegion(source, MemoryPageSlot(0), PageCount(3), PageDescription(
    index: PageIndex(16), access: PageAccess.ReadOnly)).error == MachineError.InvalidRange
  input[2].index = PageIndex(19)
  let gap = checked(captureMemory(input, PageLimit(3)))
  assert copyMemoryRegion(gap, MemoryPageSlot(0), PageCount(3),
    description).error == MachineError.InvalidRange
  input[2].index = PageIndex(18)
  input[2].access = PageAccess.ReadOnly
  let mixed = checked(captureMemory(input, PageLimit(3)))
  assert copyMemoryRegion(mixed, MemoryPageSlot(0), PageCount(3),
    description).error == MachineError.InvalidRange
  input[2].access = PageAccess.Inaccessible
  input[2].bytes[4095] = 91
  let inaccessible = checked(captureMemory(input, PageLimit(3)))
  assert copyMemoryRegion(inaccessible, MemoryPageSlot(0), PageCount(3),
    description).error == MachineError.InvalidRange
  assert copyMemoryRegion(inaccessible, MemoryPageSlot(2), PageCount(1), PageDescription(
    index: PageIndex(18), access: PageAccess.Inaccessible)).error == MachineError.InvalidRange
  var retained = default(array[4096, byte])
  assert checked(copyMemoryPage(inaccessible, MemoryPageSlot(2), retained)).index == PageIndex(18)
  assert retained[4095] == 91 # The complete observer still copies inaccessible retained bytes.

block lastPhysicalPageRegion:
  ## A complete page copy may include the final physical byte, unlike a wrapping scalar access.
  var input = PageImage(index: PageIndex(0xfffff), access: PageAccess.ReadOnly)
  input.bytes[4095] = 113
  let source = checked(captureMemory([input], PageLimit(1)))
  let bytes = checked(copyMemoryRegion(source, MemoryPageSlot(0), PageCount(1),
    PageDescription(index: PageIndex(0xfffff), access: PageAccess.ReadOnly)))
  for offset in 0..<4096: assert bytes[offset] == (if offset == 4095: 113'u8 else: 0'u8)

echo "PVM changed memory page slots passed"
