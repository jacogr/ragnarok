# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scalar writer identity, immutable epochs, full-byte boundary updates and atomic failure preservation.
# @@Verification={"arc": "pvm_scalar_writer_arc_release"}
import std/assertions
import std/syncio
import ../../../src/pvm/machine as pvm_machine
import ../../support/testing_arc_evidence

proc originalByte(offset: int): byte =
  ## Independently authored nonuniform bytes expose stale chunk selection and neighboring writes.
  byte((offset*37+offset div 71+19) mod 256)

proc initial(last: PageAccess = PageAccess.ReadWrite): Memory =
  ## A caller-owned page pair is captured before any private writer exists.
  var images = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte])), PageImage(index: PageIndex(17), access: last,
    bytes: default(array[4096, byte]))]
  for side in 0..<2:
    for offset in 0..<4096: images[side].bytes[offset] = originalByte(side*4096+offset)
  captureMemory(images, PageLimit(2)).value

proc expect(memory: Memory, start, width: int, value: uint64) =
  ## Check every public image byte against the initial pattern and one explicit little-endian replacement.
  for side in 0..<2:
    let image = pageImage(memory, PageIndex(uint32(16+side))).value
    for offset in 0..<4096:
      let absolute = side*4096+offset
      let relative = absolute-start
      let wanted = if relative >= 0 and relative < width:
          byte((value shr (8*relative)) and 255)
        else: originalByte(absolute)
      assert image.bytes[offset] == wanted

proc ownershipCycle() =
  ## Alias the mutable builder identity while retaining all immutable snapshots across epoch transfer.
  var source = initial()
  let writer = newScalarMemoryWriter(source).value
  let alias = writer
  assert store(writer, MemoryAddress(66047), AccessWidth(8), RegisterValue(
      0xabcdef0123456789'u64)).value
  let first = snapshotMemory(alias).value
  source = default(Memory) # The builder and snapshot own their lifetimes independently of the caller's source variable.
  assert store(alias, MemoryAddress(66047), AccessWidth(8), RegisterValue(
      0x9876543210abcdef'u64)).value
  let second = snapshotMemory(writer).value
  assert uint64(load(writer, MemoryAddress(66047), AccessWidth(8)).value) == 0x9876543210abcdef'u64
  assert uint64(load(alias, MemoryAddress(66047), AccessWidth(8)).value) == 0x9876543210abcdef'u64
  expect(first, 511, 8, 0xabcdef0123456789'u64)
  expect(second, 511, 8, 0x9876543210abcdef'u64)
  assert store(writer, MemoryAddress(66047), AccessWidth(3), RegisterValue(0)).error ==
      MachineError.InvalidWidth
  expect(snapshotMemory(alias).value, 511, 8, 0x9876543210abcdef'u64)

proc scalarReadMatrix() =
  ## Independent byte equations check zero extension and endian order through both chunk/page crossings and immutable writer epochs.
  for width in [8, 1, 4, 2]:
    for start in [0, 1, 3, 7, 503, 504, 505, 506, 507, 508, 509, 510, 511,
        512, 513, 1023, 2047, 3583, 4088, 4089, 4090, 4091, 4092, 4093, 4094, 4095]:
      var wanted = 0'u64
      for index in 0..<width: wanted = wanted or (uint64(originalByte(start+index)) shl (8*index))
      let address = MemoryAddress(uint64(65536+start))
      let access = AccessWidth(byte(width))
      let original = initial()
      let alias = original
      let writer = newScalarMemoryWriter(original).value
      assert uint64(load(original, address, access).value) == wanted
      assert uint64(load(writer, address, access).value) == wanted
      let replacement = 0xfedcba9876543210'u64
      let mask = high(uint64) shr (64-8*width)
      assert store(writer, address, access, RegisterValue(replacement)).value
      assert uint64(load(writer, address, access).value) == (replacement and mask)
      let frozen = snapshotMemory(writer).value
      assert uint64(load(frozen, address, access).value) == (replacement and mask)
      assert store(writer, address, access, RegisterValue(not replacement)).value
      assert uint64(load(writer, address, access).value) == ((not replacement) and mask)
      assert uint64(load(frozen, address, access).value) == (replacement and mask)
      assert uint64(load(alias, address, access).value) == wanted

proc expectBytes(memory: Memory, expected: array[8192, byte]) =
  ## Compare full independent page images, including every neighbor outside either overlapping scalar write.
  for side in 0..<2:
    let image = pageImage(memory, PageIndex(uint32(16+side))).value
    assert image.access == PageAccess.ReadWrite
    for offset in 0..<4096: assert image.bytes[offset] == expected[side*4096+offset]

proc scalarWriteMatrix() =
  ## Immutable stores and aliased writer epochs produce the same exact bytes at every chunk/page edge.
  for width in [1, 2, 4, 8]:
    for start in [0, 1, 3, 503, 504, 505, 506, 507, 508, 509, 510, 511,
        512, 513, 1023, 2047, 3583, 4088, 4089, 4090, 4091, 4092, 4093, 4094, 4095]:
      let original = initial()
      let sourceAlias = original
      let writer = newScalarMemoryWriter(original).value
      let alias = writer
      let address = MemoryAddress(uint64(65536+start))
      let access = AccessWidth(byte(width))
      let value = 0xfedcba9876543210'u64
      var firstBytes = default(array[8192, byte])
      for index in 0..<8192: firstBytes[index] = originalByte(index)
      for index in 0..<width: firstBytes[start+index] = byte((value shr (8*index)) and 255)
      let first = store(original, address, access, RegisterValue(value)).value
      assert store(writer, address, access, RegisterValue(value)).value
      let frozen = snapshotMemory(alias).value
      expectBytes(first, firstBytes)
      expectBytes(frozen, firstBytes)
      let shifted = start+max(1, width div 2)
      var secondBytes = firstBytes
      for index in 0..<width: secondBytes[shifted+index] = byte(((not value) shr (8*index)) and 255)
      let second = store(first, MemoryAddress(uint64(65536+shifted)), access, RegisterValue(
          not value)).value
      assert store(alias, MemoryAddress(uint64(65536+shifted)), access, RegisterValue(
          not value)).value
      expectBytes(second, secondBytes)
      expectBytes(snapshotMemory(writer).value, secondBytes)
      expectBytes(first, firstBytes)
      expectBytes(frozen, firstBytes)
      expect(sourceAlias, 0, 0, 0)
  # A temporary source may retire after store returns; the result owns all modified and shared chunks.
  expect(store(initial(), MemoryAddress(69629), AccessWidth(8), RegisterValue(17)).value, 4093, 8, 17)

proc lookupPressureCycle() =
  ## Writer-local slot hints survive collisions/epochs while every physical tag and permission remains checked.
  var images: seq[PageImage] = @[]
  for ordinal in [16'u32, 17, 20, 64, 96, 128, 0xfffff]:
    let access = if ordinal == 17 or ordinal == 0xfffff: PageAccess.ReadOnly else: PageAccess.ReadWrite
    var image = PageImage(index: PageIndex(ordinal), access: access,
      bytes: default(array[4096, byte]))
    for index in 0..<4096: image.bytes[index] = byte((uint64(ordinal)+uint64(index)) mod 251)
    images.add(image)
  let source = captureMemory(images, PageLimit(7)).value
  let writer = newScalarMemoryWriter(source).value
  let alias = writer
  var first = default(Memory)
  var tick = 0'u64
  for ordinal in [16'u32, 20, 64, 96, 16, 128, 64, 20, 96, 128, 16]:
    # Five sparse pages exceed the retained slots; hits and evictions must resolve exact physical tags.
    let base = uint64(ordinal)*4096
    assert uint64(load(alias, MemoryAddress(base+1), AccessWidth(1)).value) == uint64((
        ordinal+1) mod 251)
    let value = 0xfedcba9876543210'u64 xor tick
    assert store(writer, MemoryAddress(base+511), AccessWidth(8), RegisterValue(value)).value
    assert uint64(load(alias, MemoryAddress(base+511), AccessWidth(8)).value) == value
    let frozen = snapshotMemory(alias).value
    if tick == 0: first = frozen # A retained earlier epoch must never observe later cache hits or writes.
    assert uint64(load(frozen, MemoryAddress(base+511), AccessWidth(8)).value) == value
    inc tick
  assert uint64(load(first, MemoryAddress(66047), AccessWidth(8)).value) == 0xfedcba9876543210'u64
  assert uint64(load(writer, MemoryAddress(0x100040001'u64), AccessWidth(1)).value) == 65'u64
  # A cached readable page still cannot receive writes; scalar wrapping remains distinct from natural host ranges.
  assert load(alias, MemoryAddress(69632), AccessWidth(1)).error == MachineError.None
  let readonly = store(alias, MemoryAddress(69632), AccessWidth(1), RegisterValue(0))
  assert readonly.error == MachineError.Fault and uint32(readonly.faultPage) == 69632
  let missing = load(writer, MemoryAddress(73728), AccessWidth(1))
  assert missing.error == MachineError.Fault and uint32(missing.faultPage) == 73728
  assert load(writer, MemoryAddress(65536), AccessWidth(3)).error == MachineError.InvalidWidth
  assert load(writer, MemoryAddress(0), AccessWidth(1)).error == MachineError.Panic
  assert load(writer, MemoryAddress(0xfffffffe'u64), AccessWidth(1)).error == MachineError.None
  assert load(writer, MemoryAddress(0xffffffff'u64), AccessWidth(1)).error == MachineError.Panic
  assert store(writer, MemoryAddress(0xffffffff'u64), AccessWidth(1), RegisterValue(0)).error ==
      MachineError.Panic
  # A readable first RO page must not hide the missing second-page precedence for a crossing store.
  var only = images[0]
  only.access = PageAccess.ReadOnly
  let separate = newScalarMemoryWriter(captureMemory([only], PageLimit(1)).value).value
  assert load(separate, MemoryAddress(69631), AccessWidth(1)).error == MachineError.None
  let crossing = store(separate, MemoryAddress(69631), AccessWidth(2), RegisterValue(0))
  assert crossing.error == MachineError.Fault and uint32(crossing.faultPage) == 69632
  for image in images:
    let original = pageImage(source, image.index).value
    for index in 0..<4096: assert original.bytes[index] == image.bytes[index]

proc temporaryReadCycle() =
  ## Constructor-only owners survive each complete scalar read and release afterward; no copied chunk address or machine owner escapes.
  for start in [511, 4093]:
    var wanted = 0'u64
    for index in 0..<8: wanted = wanted or (uint64(originalByte(start+index)) shl (8*index))
    let address = MemoryAddress(uint64(65536+start))
    let ordinary = load(initial(), address, AccessWidth(8))
    let staged = load(newScalarMemoryWriter(initial()).value, address, AccessWidth(8))
    assert uint64(ordinary.value) == wanted and uint64(staged.value) == wanted
  let narrow = load(initial(), MemoryAddress(65537), AccessWidth(1))
  assert uint64(narrow.value) == uint64(originalByte(1))

let missing: nil ScalarMemoryWriter = nil
assert load(missing, MemoryAddress(0), AccessWidth(0)).error == MachineError.InvalidOwner
assert store(missing, MemoryAddress(0), AccessWidth(0), RegisterValue(0)).error ==
    MachineError.InvalidOwner
assert snapshotMemory(missing).error == MachineError.InvalidOwner
assert newScalarMemoryWriter(default(Memory)).error == MachineError.InvalidOwner
for width in [1, 2, 4, 8]:
  for start in [0, 505, 509, 511, 512, 1023, 2047, 3583, 4093, 4095]:
    let memory = initial()
    let writer = newScalarMemoryWriter(memory).value
    expect(snapshotMemory(writer).value, 0, 0, 0)
    let value = 0xfedcba9876543210'u64
    assert store(writer, MemoryAddress(uint64(65536+start)), AccessWidth(byte(width)),
        RegisterValue(value)).value
    let frozen = snapshotMemory(writer).value
    expect(frozen, start, width, value)
    expect(memory, 0, 0, 0)
    let mask = high(uint64) shr (64-8*width)
    assert uint64(load(writer, MemoryAddress(uint64(65536+start)), AccessWidth(byte(
        width))).value) == (value and mask)
# A failed second-page preflight preserves earlier private progress and never writes its accessible prefix.
let readonly = initial(PageAccess.ReadOnly)
let blocked = newScalarMemoryWriter(readonly).value
assert store(blocked, MemoryAddress(65536), AccessWidth(8), RegisterValue(7)).value
let refused = store(blocked, MemoryAddress(69631), AccessWidth(8), RegisterValue(high(uint64)))
assert refused.error == MachineError.Fault and uint32(refused.faultPage) == 69632
expect(snapshotMemory(blocked).value, 0, 8, 7)
expect(readonly, 0, 0, 0)
let empty = newScalarMemoryWriter(captureMemory([], PageLimit(0)).value).value
assert load(empty, MemoryAddress(65536), AccessWidth(1)).error == MachineError.Fault
assert pageImage(snapshotMemory(empty).value, PageIndex(16)).value.access == PageAccess.Inaccessible
ownershipCycle()
scalarWriteMatrix()
lookupPressureCycle()
scalarReadMatrix()
temporaryReadCycle()
let before = getOccupiedMem()
for cycle in 0..<1000:
  lookupPressureCycle() # Cached physical slots retain no page owner across complete writer/epoch retirement.
  temporaryReadCycle() # Temporary argument roots retire only after copied scalar results are complete.
  ownershipCycle() # Builder aliases, epoch snapshots and transferred vectors release without cycles or double retirement.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_scalar_writer", 1000, before, after)
echo "PVM scalar working memory passed"
echo "ARC_RELEASE cycles=1000 unchanged"
