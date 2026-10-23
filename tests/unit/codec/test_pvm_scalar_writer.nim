# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scalar writer identity, immutable epochs, full-byte boundary updates and atomic failure preservation.
# @@Verification={"arc": "pvm_scalar_writer_arc_release"}
import std/[assertions, syncio]
import ../../../src/pvm/machine
import ../../support/arc_evidence

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
let before = getOccupiedMem()
for cycle in 0..<1000:
  ownershipCycle() # Builder aliases, epoch snapshots and transferred vectors release without cycles or double retirement.
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_scalar_writer", 1000, before, after)
echo "PVM scalar working memory passed"
echo "ARC_RELEASE cycles=1000 unchanged"
