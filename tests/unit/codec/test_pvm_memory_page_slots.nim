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

echo "PVM changed memory page slots passed"
