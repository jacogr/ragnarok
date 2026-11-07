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

proc residentBytes(memory: Memory, first: uint32, count: uint32,
    access: PageAccess = PageAccess.ReadWrite): seq[byte] =
  ## Observe a fresh owned region at slot zero without exposing its immutable backing or proofs.
  var copied = copyMemoryRegion(memory, MemoryPageSlot(0), PageCount(count),
    PageDescription(index: PageIndex(first), access: access))
  assert copied.error == MachineError.None
  takeValue(copied)

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
  let layout = memoryLayout(captured).value
  assert layout.len == images.len
  var output = newSeq[byte](4096)
  for slot in 0..<layout.len:
    # Positional copies preserve all bytes/access tags, including low inaccessible and highest physical pages.
    let copiedPage = copyMemoryPage(captured, MemoryPageSlot(uint32(slot)), output)
    assert copiedPage.error == MachineError.None
    assert uint32(copiedPage.value.index) == uint32(images[slot].index)
    assert copiedPage.value.access == images[slot].access
    assert uint32(layout[slot].index) == uint32(images[slot].index)
    assert layout[slot].access == images[slot].access
    for offset in 0..<output.len: assert output[offset] == byteAt(slot*4096+offset)
    let matching = matchesMemoryPageBytes(captured, MemoryPageSlot(uint32(slot)),
        layout[slot], output)
    assert matching.error == MachineError.None and matching.value
    for boundary in [0, 511, 512, 4095]:
      output[boundary] = output[boundary] xor 255'u8
      let different = matchesMemoryPageBytes(captured, MemoryPageSlot(uint32(slot)),
          layout[slot], output)
      assert different.error == MachineError.None and not different.value
      output[boundary] = output[boundary] xor 255'u8
    assert matchesMemoryPageBytes(captured, MemoryPageSlot(uint32(slot)),
        layout[slot], output).value
  var wrongIndex = layout[0]
  wrongIndex.index = PageIndex(18)
  var wrongAccess = layout[0]
  wrongAccess.access = PageAccess.ReadWrite
  assert matchesMemoryPageBytes(captured, MemoryPageSlot(0), wrongIndex, output).error ==
      MachineError.InvalidRange
  assert matchesMemoryPageBytes(captured, MemoryPageSlot(0), wrongAccess, output).error ==
      MachineError.InvalidRange
  assert matchesMemoryPageBytes(captured, MemoryPageSlot(3), layout[0], output).error ==
      MachineError.InvalidRange
  assert matchesMemoryPageBytes(default(Memory), MemoryPageSlot(0), layout[0], output).error ==
      MachineError.InvalidOwner
  assert matchesMemoryPageBytes(captured, MemoryPageSlot(0), layout[0],
      output.toOpenArray(0, 4094)).error == MachineError.InvalidRange
  for offset in 0..<output.len: output[offset] = 77
  assert copyMemoryPage(captured, MemoryPageSlot(3), output).error == MachineError.InvalidRange
  assert copyMemoryPage(default(Memory), MemoryPageSlot(0), output).error ==
      MachineError.InvalidOwner
  assert memoryLayout(default(Memory)).error == MachineError.InvalidOwner
  assert copyMemoryPage(captured, MemoryPageSlot(0), output.toOpenArray(0, 4094)).error ==
      MachineError.InvalidRange
  for offset in 0..<output.len:
    # Every rejected request is atomic with respect to the caller's output buffer.
    assert output[offset] == 77
  var observation = memoryImages(captured)
  assert observation.error == MachineError.None
  let copied = observation.value
  var transferred = takeValue(observation)
  assert observation.error == MachineError.Uninitialized and transferred.len == 3
  for side in 0..<transferred.len:
    # Transferring a copied observation never transfers the immutable source's chunks or earlier copies.
    transferred[side].bytes[0] = transferred[side].bytes[0] xor 255'u8
    let retained = pageImage(captured, images[side].index).value
    assert retained.bytes[0] == byteAt(side*4096) and copied[side].bytes[0] == retained.bytes[0]
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

proc zeroCycle() =
  ## Writes to shared known-zero storage must isolate every chunk, page, permission alias and sealed writer epoch.
  let blank = captureMemory([], PageLimit(4)).value
  assert withWritablePages(blank, PageIndex(16), PageIndex(21)).error == MachineError.LimitExceeded
  let mapped = withWritablePages(blank, PageIndex(16), PageIndex(20)).value
  let dirty = store(mapped, MemoryAddress(65539), AccessWidth(1), RegisterValue(99)).value
  let cleared = withPageRange(dirty, PageIndex(16), PageIndex(20), PageAccess.ReadWrite,
    PageContent.Zeroed).value
  let readonly = withPageRange(cleared, PageIndex(16), PageIndex(20), PageAccess.ReadOnly,
    PageContent.Preserved).value
  let partial = withWritablePages(readonly, PageIndex(17), PageIndex(18)).value
  assert store(readonly, MemoryAddress(69632), AccessWidth(1), RegisterValue(9)).error ==
      MachineError.Fault
  assert store(mapped, MemoryAddress(81916), AccessWidth(8), RegisterValue(9)).error ==
      MachineError.Fault
  let private = store(partial, MemoryAddress(69633), AccessWidth(1), RegisterValue(23)).value
  let writer = newScalarMemoryWriter(mapped).value
  let alias = writer
  assert store(writer, MemoryAddress(66047), AccessWidth(8), RegisterValue(
      0x0807060504030201'u64)).error == MachineError.None
  let first = snapshotMemory(writer).value
  assert store(alias, MemoryAddress(70143), AccessWidth(8), RegisterValue(
      0x1817161514131211'u64)).error == MachineError.None
  let second = snapshotMemory(alias).value
  var input = newSeq[byte](1026)
  for index in 0..<input.len: input[index] = byte((index*17+3) mod 251)
  let bulk = writeBytes(cleared, MemoryAddress(74238), input, MemoryByteLimit(1026)).value
  let scalar = store(cleared, MemoryAddress(81914), AccessWidth(4), RegisterValue(
      0x44332211'u64)).value
  # The existing repeated ARC cycle owns and retires a fresh region alongside all old observations.
  let resident = residentBytes(scalar, 16, 4)
  for side in 0..<4:
    # Independent expectations expose unintended writes to another chunk/page that happens to share the same zero child.
    let index = PageIndex(uint32(16+side))
    let original = pageImage(mapped, index).value
    let old = pageImage(dirty, index).value
    let zero = pageImage(cleared, index).value
    let protected = pageImage(readonly, index).value
    let changed = pageImage(private, index).value
    let one = pageImage(first, index).value
    let two = pageImage(second, index).value
    let many = pageImage(bulk, index).value
    let word = pageImage(scalar, index).value
    assert original.access == PageAccess.ReadWrite and zero.access == PageAccess.ReadWrite
    assert protected.access == PageAccess.ReadOnly
    assert changed.access == (if side == 1: PageAccess.ReadWrite else: PageAccess.ReadOnly)
    for offset in 0..<4096:
      assert original.bytes[offset] == 0 and zero.bytes[offset] == 0 and protected.bytes[offset] == 0
      assert old.bytes[offset] == (if side == 0 and offset == 3: 99'u8 else: 0'u8)
      assert changed.bytes[offset] == (if side == 1 and offset == 1: 23'u8 else: 0'u8)
      let a = if side == 0 and offset >= 511 and offset < 519: byte(offset-510) else: 0'u8
      let b = if side == 1 and offset >= 511 and offset < 519: byte(offset-494) else: a
      assert one.bytes[offset] == a and two.bytes[offset] == b
      let relative = side*4096+offset-8702
      assert many.bytes[offset] == (if relative >= 0 and relative < 1026: byte((
          relative*17+3) mod 251) else: 0'u8)
      let octet = if side == 3 and offset >= 4090 and offset < 4094:
          byte((0x44332211'u64 shr (8*(offset-4090))) and 255)
        else: 0'u8
      assert word.bytes[offset] == octet
      assert resident[side*4096+offset] == octet
  let dropped = withPageRange(cleared, PageIndex(16), PageIndex(20), PageAccess.Inaccessible,
    PageContent.Zeroed).value
  assert uint32(writablePageCount(dropped, PageIndex(16), PageIndex(20)).value) == 0
  let remapped = withWritablePages(dropped, PageIndex(16), PageIndex(20)).value
  for side in 0..<4:
    let gone = pageImage(dropped, PageIndex(uint32(16+side))).value
    let restored = pageImage(remapped, PageIndex(uint32(16+side))).value
    assert gone.access == PageAccess.Inaccessible and restored.access == PageAccess.ReadWrite
    for offset in 0..<4096: assert gone.bytes[offset] == 0 and restored.bytes[offset] == 0
  assert uint32(writablePageCount(blank, PageIndex(16), PageIndex(20)).value) == 0

proc replacementFromTemporary(different: bool): Memory =
  ## The returned successor must own its shared bytes after both caller image and parent retire.
  var image = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  for offset in 0..<4096:
    # The expected pattern belongs to the fixture, independently of any returned page storage.
    image.bytes[offset] = byteAt(offset)
  let parent = captureMemory([image], PageLimit(1)).value
  if different:
    # Sparse replacement retains some parent payload while copying the authored difference.
    image.bytes[700] = image.bytes[700] xor 255'u8
  withReplacedPages(parent, [image]).value

proc replacementLifetimeCycle() =
  ## Equal and sparse successors remain complete after the temporary parent scope has ended.
  for different in [false, true]:
    let successor = replacementFromTemporary(different)
    let observed = pageImage(successor, PageIndex(16)).value
    assert observed.access == PageAccess.ReadWrite
    for offset in 0..<4096:
      # Check all retained payloads, including the last chunk and the independently copied byte.
      let expected = if different and offset == 700: byteAt(offset) xor 255'u8 else: byteAt(offset)
      assert observed.bytes[offset] == expected

proc replacementCycle() =
  ## Whole-page public observations cover equal, one-chunk, cross-chunk and all-chunk replacement ownership.
  var input = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  for offset in 0..<4096:
    # Nonuniform bytes expose stale neighboring payloads in every retained generation.
    input.bytes[offset] = byteAt(offset)
  let original = captureMemory([input], PageLimit(1)).value
  for variant in 0..<4:
    # Explicit equal-byte replacement must still publish a fresh page identity and delta slot.
    var replacement = input
    for offset in 0..<4096:
      # Independent byte equations author exactly zero, one, two or all eight changed chunks.
      if (variant == 1 and offset == 700) or
          (variant == 2 and offset >= 509 and offset < 517) or variant == 3:
        replacement.bytes[offset] = byteAt(offset) xor 255'u8
    let expected = replacement.bytes
    let changed = withReplacedPages(original, [replacement]).value
    assert not samePage(original, changed, PageIndex(16))
    assert changedMemoryPageSlots(original, changed).value == @[MemoryPageSlot(0)]
    assert changedMemoryPageSlots(changed, original).value == @[MemoryPageSlot(0)]
    for offset in 0..<4096:
      # Mutating the caller after construction must never alter either published owner.
      replacement.bytes[offset] = 0
    let predecessor = pageImage(original, PageIndex(16)).value
    let observed = pageImage(changed, PageIndex(16)).value
    for offset in 0..<4096:
      assert predecessor.bytes[offset] == byteAt(offset)
      assert observed.bytes[offset] == expected[offset]
  # A literal little-endian scalar straddles a chunk boundary in the replacement image.
  var crossed = input
  for octet in 0..<8:
    crossed.bytes[509+octet] = byte((0x8877665544332211'u64 shr (octet*8)) and 255)
  let crossing = withReplacedPages(original, [crossed]).value
  assert uint64(load(crossing, MemoryAddress(65536+509), AccessWidth(
      8)).value) ==
    0x8877665544332211'u64
  let predecessor = pageImage(original, PageIndex(16)).value
  for offset in 0..<4096:
    assert predecessor.bytes[offset] == byteAt(offset)
  # A later invalid item must refuse the full replacement before any valid prefix becomes observable.
  var absent = input
  absent.index = PageIndex(17)
  assert withReplacedPages(original, [crossed, absent]).error ==
      MachineError.InvalidRange
  assert withReplacedPages(original, [crossed, crossed]).error ==
      MachineError.UnsortedPages
  var wrongAccess = crossed
  wrongAccess.access = PageAccess.ReadOnly
  assert withReplacedPages(original, [wrongAccess]).error ==
      MachineError.InvalidRange

proc replacementWriterCycle() =
  ## Sharing from a sealed writer epoch must survive later writes through both the old and replacement writer.
  var input = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  for offset in 0..<4096:
    # Track all bytes, including untouched chunks shared with the original captured memory.
    input.bytes[offset] = byteAt(offset)
  let original = captureMemory([input], PageLimit(1)).value
  let writer = newScalarMemoryWriter(original).value
  assert store(writer, MemoryAddress(65536+509), AccessWidth(8),
    RegisterValue(0x8877665544332211'u64)).error == MachineError.None
  let sealed = snapshotMemory(writer).value
  var replacement = pageImage(sealed, PageIndex(16)).value
  replacement.bytes[1600] = replacement.bytes[1600] xor 255'u8
  let replaced = withReplacedPages(sealed, [replacement]).value
  replacement.bytes[0] = 0 # The replacement also owns its differing chunk independently of input mutation.
  # Resume the original epoch in a shared formerly-private chunk and an untouched shared chunk.
  assert store(writer, MemoryAddress(65536+509), AccessWidth(8), RegisterValue(
      0)).error == MachineError.None
  assert store(writer, MemoryAddress(65536+3000), AccessWidth(1), RegisterValue(
      17)).error == MachineError.None
  let later = snapshotMemory(writer).value
  let nextWriter = newScalarMemoryWriter(replaced).value
  assert store(nextWriter, MemoryAddress(65536+510), AccessWidth(2),
      RegisterValue(0xffff)).error == MachineError.None
  assert store(nextWriter, MemoryAddress(65536+1600), AccessWidth(1),
      RegisterValue(33)).error == MachineError.None
  let next = snapshotMemory(nextWriter).value
  let a = pageImage(original, PageIndex(16)).value
  let b = pageImage(sealed, PageIndex(16)).value
  let c = pageImage(replaced, PageIndex(16)).value
  let d = pageImage(later, PageIndex(16)).value
  let e = pageImage(next, PageIndex(16)).value
  for offset in 0..<4096:
    # Authored literals define each generation independently of the memory implementation.
    let initial = byteAt(offset)
    let first = if offset >= 509 and offset < 517:
        byte((0x8877665544332211'u64 shr ((offset-509)*8)) and 255)
      else: initial
    let second = if offset == 1600: first xor 255'u8 else: first
    let resumed = if offset >= 509 and offset < 517: 0'u8
      elif offset == 3000: 17'u8 else: first
    let final = if offset == 510 or offset == 511: 255'u8
      elif offset == 1600: 33'u8 else: second
    assert a.bytes[offset] == initial and b.bytes[offset] == first
    assert c.bytes[offset] == second and d.bytes[offset] == resumed and e.bytes[
        offset] == final

proc residentPrefixCycle() =
  ## A partial chunk must copy its nonzero prefix while wholly uncovered chunks remain zero.
  for length in [0, 1, 511, 512, 513, 4095, 4096, 4097, 8191, 8192]:
    # Source bytes are all nonzero so an overly broad zero proof cannot pass the output oracle.
    var input = newSeq[byte](length)
    for offset in 0..<input.len: input[offset] = byte((offset*7+13) mod 251+1)
    let regions = [InitializationRegion(first: PageIndex(16), past: PageIndex(18),
      access: PageAccess.ReadWrite, source: InitializationSource.First, offset: 0, length: length)]
    let captured = captureInitializationMemory(regions, input, [], PageLimit(2))
    assert captured.error == MachineError.None
    let source = captured.value
    var first = residentBytes(source, 16, 2)
    let second = residentBytes(source, 16, 2)
    if input.len > 0: input[0] = 0 # No returned region can borrow a caller's prefix.
    first[8191] = 91
    var overwritten = default(array[4096, byte])
    for offset in 0..<overwritten.len: overwritten[offset] = 77
    assert copyMemoryPage(source, MemoryPageSlot(1), overwritten).error == MachineError.None
    let firstPage = pageImage(source, PageIndex(16)).value
    let secondPage = pageImage(source, PageIndex(17)).value
    for offset in 0..<8192:
      # The second copy and complete predecessor observations retain every literal byte.
      let expected = if offset < length: byte((offset*7+13) mod 251+1) else: 0'u8
      assert first[offset] == (if offset == 8191: 91'u8 else: expected)
      assert second[offset] == expected
      let original = if offset < 4096: firstPage.bytes[offset] else: secondPage.bytes[offset-4096]
      assert original == expected
      if offset >= 4096: assert overwritten[offset-4096] == expected

proc residentProofCycle() =
  ## Recopy mutations of proven-zero pages through each page construction and writer ownership path.
  let empty = captureMemory([], PageLimit(3)).value
  let original = withWritablePages(empty, PageIndex(16), PageIndex(19)).value
  let readonly = withPageRange(original, PageIndex(16), PageIndex(19), PageAccess.ReadOnly,
    PageContent.Preserved).value
  let writable = withWritablePages(readonly, PageIndex(16), PageIndex(19)).value
  let baseline = residentBytes(readonly, 16, 3, PageAccess.ReadOnly)
  for width in [1, 2, 4, 8]:
    for offset in [511, 512, 4093, 4095]:
      # Complete scalar preflight and first-write cloning precede either side of a chunk/page edge.
      let changed = store(writable, MemoryAddress(uint64(65536+offset)), AccessWidth(byte(width)),
        RegisterValue(0x8877665544332211'u64)).value
      let bytes = residentBytes(changed, 16, 3)
      for at in 0..<bytes.len:
        let expected = if at >= offset and at-offset < width:
            byte((0x8877665544332211'u64 shr ((at-offset)*8)) and 255)
          else: 0'u8
        assert bytes[at] == expected and baseline[at] == 0
  let payload = [13'u8, 27, 39, 51, 63, 75, 87, 99]
  let bulk = writeBytes(writable, MemoryAddress(65536+4093), payload,
    MemoryByteLimit(uint64(payload.len))).value
  var image = pageImage(writable, PageIndex(17)).value
  image.bytes[512] = 61
  let replaced = withReplacedPages(writable, [image]).value
  image.bytes[513] = 83
  let inserted = withPage(writable, image).value
  var batch = beginResidentReplacements(writable)
  var page = default(array[4096, byte])
  page[511] = 107
  assert stageResidentPage(batch, MemoryPageSlot(2), PageDescription(index: PageIndex(18),
    access: PageAccess.ReadWrite), page) == MachineError.None
  let published = finishResidentReplacements(batch).value
  let hidden = withPageRange(inserted, PageIndex(16), PageIndex(19), PageAccess.Inaccessible,
    PageContent.Preserved).value
  let restored = withWritablePages(hidden, PageIndex(16), PageIndex(19)).value
  let cleared = withPageRange(restored, PageIndex(16), PageIndex(19), PageAccess.ReadWrite,
    PageContent.Zeroed).value
  let bulkBytes = residentBytes(bulk, 16, 3)
  let replacementBytes = residentBytes(replaced, 16, 3)
  let insertionBytes = residentBytes(inserted, 16, 3)
  let publishedBytes = residentBytes(published, 16, 3)
  let restoredBytes = residentBytes(restored, 16, 3)
  let clearedBytes = residentBytes(cleared, 16, 3)
  for at in 0..<baseline.len:
    # Literal offsets distinguish public replacement, resident publication and permission retention.
    assert bulkBytes[at] == (if at >= 4093 and at < 4101: payload[at-4093] else: 0'u8)
    assert replacementBytes[at] == (if at == 4608: 61'u8 else: 0'u8)
    let expected = if at == 4608: 61'u8 elif at == 4609: 83'u8 else: 0'u8
    assert insertionBytes[at] == expected and restoredBytes[at] == expected
    assert publishedBytes[at] == (if at == 8703: 107'u8 else: 0'u8)
    assert clearedBytes[at] == 0 and baseline[at] == 0
  let writer = newScalarMemoryWriter(writable).value
  let alias = writer
  assert store(writer, MemoryAddress(65540), AccessWidth(1), RegisterValue(0)).error ==
    MachineError.None
  assert store(writer, MemoryAddress(65540), AccessWidth(1), RegisterValue(71)).error ==
    MachineError.None
  assert store(writer, MemoryAddress(69636), AccessWidth(1), RegisterValue(0)).error ==
    MachineError.None
  assert store(writer, MemoryAddress(65540), AccessWidth(1), RegisterValue(73)).error ==
    MachineError.None
  assert store(writer, MemoryAddress(69636), AccessWidth(1), RegisterValue(91)).error ==
    MachineError.None
  let first = snapshotMemory(writer).value
  assert store(alias, MemoryAddress(65540), AccessWidth(1), RegisterValue(19)).error ==
    MachineError.None
  let second = snapshotMemory(alias).value
  let firstBytes = residentBytes(first, 16, 3)
  let secondBytes = residentBytes(second, 16, 3)
  let predecessor = residentBytes(original, 16, 3)
  for at in 0..<baseline.len:
    # Zero first writes, cache hits and later alias epochs must not keep stale proofs.
    assert firstBytes[at] == (if at == 4: 73'u8 elif at == 4100: 91'u8 else: 0'u8)
    assert secondBytes[at] == (if at == 4: 19'u8 elif at == 4100: 91'u8 else: 0'u8)
    assert predecessor[at] == 0

residentPrefixCycle()
residentProofCycle()
snapshotCycle()
captureCycle()
observationCycle()
zeroCycle()
replacementLifetimeCycle()
replacementCycle()
replacementWriterCycle()
let before = getOccupiedMem()
for cycle in 0..<1000:
  snapshotCycle() # Private chunk/header owners and every retained generation must retire without cycles.
  captureCycle()
  observationCycle()
  zeroCycle()
  replacementLifetimeCycle()
  replacementCycle()
  replacementWriterCycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_memory_chunks", 1000, before, after)
echo "PVM persistent page snapshots passed"
echo "ARC_RELEASE cycles=1000 unchanged"
