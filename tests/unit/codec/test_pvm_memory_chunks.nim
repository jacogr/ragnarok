# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Persistent page storage preserves full-byte predecessor snapshots across scalar, host and permission updates.
# @@Verification={"arc": "pvm_memory_chunks_arc_release"}
import std/[assertions, syncio]
import ../../../src/pvm/machine
import ../../support/arc_evidence

proc byteAt(offset: int): byte =
  ## An independent nonuniform pattern exposes accidental neighboring writes and stale chunk selection.
  byte((offset*37+offset div 71+19) mod 256)

proc snapshotCycle() =
  ## Retain all mutation generations and permission aliases until complete page observations finish.
  var images = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte])), PageImage(index: PageIndex(17),
        access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))]
  for side in 0..<2:
    for index in 0..<4096: images[side].bytes[index] = byteAt(side*4096+index)
  let original = captureMemory(images, PageLimit(2)).value
  let readonly = withPageRange(original, PageIndex(16), PageIndex(18), PageAccess.ReadOnly,
      PageContent.Preserved).value
  let writable = withWritablePages(readonly, PageIndex(16), PageIndex(18)).value
  for boundary in [256, 512, 1024, 1536, 2048, 2560, 3072, 3584, 4096]:
    let start = boundary-3
    let address = MemoryAddress(uint64(65536+start))
    let first = store(writable, address, AccessWidth(8), RegisterValue(
        0x9876543210abcdef'u64)).value
    let second = store(first, MemoryAddress(uint64(65536+start+1)), AccessWidth(2), RegisterValue(0x1234)).value
    var input = newSeq[byte](20)
    for index in 0..<input.len: input[index] = byte(index+100)
    let host = writeBytes(second, MemoryAddress(uint64(65536+start-2)), input, MemoryByteLimit(20)).value
    input[0] = 0 # A completed host snapshot must own copied bytes independently of caller mutation.
    assert writeBytes(second, address, input, MemoryByteLimit(19)).error ==
        MachineError.LimitExceeded
    assert store(readonly, address, AccessWidth(8), RegisterValue(0)).error == MachineError.Fault
    for side in 0..<2:
      let before = pageImage(original, PageIndex(uint32(16+side))).value
      let protected = pageImage(readonly, PageIndex(uint32(16+side))).value
      let remapped = pageImage(writable, PageIndex(uint32(16+side))).value
      let one = pageImage(first, PageIndex(uint32(16+side))).value
      let two = pageImage(second, PageIndex(uint32(16+side))).value
      let final = pageImage(host, PageIndex(uint32(16+side))).value
      assert before.access == PageAccess.ReadWrite and protected.access == PageAccess.ReadOnly
      assert remapped.access == PageAccess.ReadWrite and final.access == PageAccess.ReadWrite
      for index in 0..<4096:
        # Expected bytes come only from authored updates and the independent initial pattern.
        let absolute = side*4096+index
        let relative = absolute-start
        let initial = byteAt(absolute)
        let firstByte = if relative >= 0 and relative < 8:
            byte((0x9876543210abcdef'u64 shr (8*relative)) and 255)
          else: initial
        let secondByte = if relative == 1: 0x34'u8 elif relative == 2: 0x12'u8 else: firstByte
        let hostByte = if relative >= -2 and relative < 18: byte(relative+102) else: secondByte
        assert before.bytes[index] == initial and protected.bytes[index] == initial
        assert remapped.bytes[index] == initial and one.bytes[index] == firstByte
        assert two.bytes[index] == secondByte and final.bytes[index] == hostByte
  images[0].bytes[0] = 0
  assert pageImage(original, PageIndex(16)).value.bytes[0] == byteAt(0)

proc captureCycle() =
  ## Observe all chunks and permission alternatives independently of caller and returned-image mutations.
  var images = [PageImage(index: PageIndex(0), access: PageAccess.Inaccessible,
    bytes: default(array[4096, byte])), PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
    bytes: default(array[4096, byte])), PageImage(index: PageIndex(0xfffff),
        access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))]
  for side in 0..<3:
    for index in 0..<4096: images[side].bytes[index] = byteAt(side*4096+index)
  assert captureMemory(images, PageLimit(2)).error == MachineError.LimitExceeded
  let captured = captureMemory(images, PageLimit(3)).value
  for side in 0..<3:
    let ordinal = images[side].index
    let access = images[side].access
    for index in 0..<4096: images[side].bytes[index] = 0
    var copied = pageImage(captured, ordinal).value
    assert uint32(copied.index) == uint32(ordinal) and copied.access == access
    for index in 0..<4096: assert copied.bytes[index] == byteAt(side*4096+index)
    copied.index = PageIndex(7)
    copied.access = PageAccess.Inaccessible
    for index in 0..<4096: copied.bytes[index] = 255
    let again = pageImage(captured, ordinal).value
    assert uint32(again.index) == uint32(ordinal) and again.access == access
    for index in 0..<4096: assert again.bytes[index] == byteAt(side*4096+index)
  # Replacement must capture the complete caller image without modifying any predecessor or hidden bytes.
  let replacement = withPage(captured, images[1]).value
  for side in 0..<3:
    let prior = pageImage(captured, images[side].index).value
    let next = pageImage(replacement, images[side].index).value
    for index in 0..<4096:
      assert prior.bytes[index] == byteAt(side*4096+index)
      assert next.bytes[index] == (if side == 1: 0'u8 else: byteAt(side*4096+index))
proc temporaryImage(): PageImage =
  ## A copied observation remains valid after the temporary source image and final memory owner both retire.
  var image = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
    bytes: default(array[4096, byte]))
  for index in 0..<4096: image.bytes[index] = byteAt(index)
  let owner = captureMemory([image], PageLimit(1)).value
  pageImage(owner, PageIndex(16)).value
proc observationCycle() =
  ## Exercise returned copied storage after its parent lifetime, including both end chunks.
  let observed = temporaryImage()
  assert uint32(observed.index) == 16 and observed.access == PageAccess.ReadOnly
  for index in 0..<4096: assert observed.bytes[index] == byteAt(index)

snapshotCycle()
captureCycle()
observationCycle()
let before = getOccupiedMem()
for cycle in 0..<1000:
  snapshotCycle() # Private chunk/header owners and every retained generation must retire without cycles.
  captureCycle()
  observationCycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_memory_chunks", 1000, before, after)
echo "PVM persistent page snapshots passed"
echo "ARC_RELEASE cycles=1000 unchanged"
