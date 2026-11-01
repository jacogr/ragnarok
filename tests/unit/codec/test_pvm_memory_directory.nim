# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_memory_directory_arc_release"}
## Public snapshot checks exercise directory boundaries, sparse batches and retained writer epochs.
import std/[assertions, syncio]
import ../../../src/pvm/machine
import ../../support/arc_evidence

proc verify(memory: Memory, expected: openArray[PageImage]) =
  ## Check complete bytes and copied metadata rather than internal block identities.
  let layout = memoryLayout(memory)
  assert layout.error == MachineError.None and layout.value.len == expected.len
  for index in 0..<expected.len:
    # Every logical slot must keep its genuine physical index and permission after root sharing.
    let observed = pageImage(memory, expected[index].index)
    assert observed.error == MachineError.None
    assert uint32(layout.value[index].index) == uint32(expected[index].index)
    assert observed.value.access == expected[index].access
    assert observed.value.bytes == expected[index].bytes

proc releaseCycle() =
  ## Retire a partial final block, shared predecessors, host copies and aliased writer epochs together.
  var pages = newSeq[PageImage](129)
  for index in 0..<pages.len:
    pages[index] = PageImage(index: PageIndex(uint32(16+index)), access: PageAccess.ReadWrite)
  let source = captureMemory(pages, PageLimit(129)).value
  let updated = store(source, MemoryAddress(uint64(16+63)*4096+4094), AccessWidth(8),
    RegisterValue(0x123456789abcdef0'u64)).value
  let payload = [1'u8, 2, 3, 4]
  let hosted = writeBytes(updated, MemoryAddress(uint64(16+127)*4096+4094), payload,
    MemoryByteLimit(4)).value
  let writer = newScalarMemoryWriter(hosted).value
  let alias = writer
  assert store(writer, MemoryAddress(uint64(16+64)*4096+511), AccessWidth(8),
    RegisterValue(0xfedcba9876543210'u64)).error == MachineError.None
  let first = snapshotMemory(writer).value
  assert store(alias, MemoryAddress(uint64(16+128)*4096+127), AccessWidth(1),
    RegisterValue(99)).error == MachineError.None
  let second = snapshotMemory(alias).value
  assert pageImage(source, PageIndex(79)).value.bytes[4094] == 0
  assert pageImage(first, PageIndex(144)).value.bytes[127] == 0
  assert pageImage(second, PageIndex(144)).value.bytes[127] == 99
  assert changedMemoryPages(first, second).value.len == 1

var input = newSeq[PageImage](129)
var expected = newSeq[PageImage](129)
for index in 0..<129:
  # A nonuniform independent pattern exposes neighboring-page and partial-tail confusion.
  var image = PageImage(index: PageIndex(uint32(16+index)), access: PageAccess.ReadWrite)
  for offset in 0..<4096: image.bytes[offset] = byte((index*19+offset*7+offset div 83) mod 256)
  input[index] = image
  expected[index] = image
let captured = captureMemory(input, PageLimit(130))
assert captured.error == MachineError.None
let original = captured.value
input[0].bytes[0] = input[0].bytes[0] xor 255'u8
verify(original, expected)

var denseInput = newSeq[PageImage](129)
for index in 0..<denseInput.len:
  # A complete batch exercises linear matching and replaces every block, including its partial tail.
  denseInput[index] = expected[index]
  denseInput[index].bytes[17] = byte((index*11+29) mod 256)
let dense = withReplacedPages(original, denseInput)
assert dense.error == MachineError.None
verify(dense.value, denseInput)
verify(original, expected)
let denseTail = pageImage(dense.value, PageIndex(144)).value
# Caller mutation after dense publication must not alias the copied successor's final page.
denseInput[128].bytes[17] = denseInput[128].bytes[17] xor 255'u8
assert pageImage(dense.value, PageIndex(144)).value.bytes == denseTail.bytes

var replacements: seq[PageImage] = @[]
for index in [0, 1, 62, 63, 64, 127, 128]:
  # Changes share a block, cross both block boundaries, and include the final partial block.
  var image = expected[index]
  for offset in 0..<4096: image.bytes[offset] = byte((index+offset*3+91) mod 256)
  replacements.add(image)
let changed = withReplacedPages(original, replacements)
assert changed.error == MachineError.None
verify(original, expected)
for index in 0..<replacements.len:
  # Apply literal expected images through their independently known original slots.
  let slot = [0, 1, 62, 63, 64, 127, 128][index]
  expected[slot] = replacements[index]
let batch = changed.value
verify(batch, expected)

let address = MemoryAddress(uint64(16+63)*4096+4092)
let scalar = store(batch, address, AccessWidth(8), RegisterValue(0x0123456789abcdef'u64))
assert scalar.error == MachineError.None
verify(batch, expected)
for offset in 0..<8:
  # The explicit little-endian word spans pages on opposite sides of a reference-block boundary.
  let value = byte((0x0123456789abcdef'u64 shr (offset*8)) and 255)
  if offset < 4: expected[63].bytes[4092+offset] = value
  else: expected[64].bytes[offset-4] = value
verify(scalar.value, expected)

var payload = @[1'u8, 2, 3, 4, 5, 6]
let hosted = writeBytes(scalar.value, MemoryAddress(uint64(16+127)*4096+4094),
  payload, MemoryByteLimit(6))
assert hosted.error == MachineError.None
verify(scalar.value, expected)
payload[0] = 255
expected[127].bytes[4094] = 1
expected[127].bytes[4095] = 2
for offset in 0..<4: expected[128].bytes[offset] = byte(offset+3)
verify(hosted.value, expected)

let createdWriter = newScalarMemoryWriter(hosted.value)
assert createdWriter.error == MachineError.None
let writer = createdWriter.value
let alias = writer
let writerAddress = MemoryAddress(uint64(16+64)*4096+511)
assert store(writer, writerAddress, AccessWidth(8), RegisterValue(0xfedcba9876543210'u64)).error ==
    MachineError.None
let firstEpoch = snapshotMemory(writer)
assert firstEpoch.error == MachineError.None
verify(hosted.value, expected)
for offset in 0..<8:
  # This write crosses a chunk boundary while staying within one directory page.
  expected[64].bytes[511+offset] = byte((0xfedcba9876543210'u64 shr (offset*8)) and 255)
verify(firstEpoch.value, expected)
assert store(alias, MemoryAddress(uint64(16+128)*4096+100), AccessWidth(1), RegisterValue(
    77)).error == MachineError.None
let secondEpoch = snapshotMemory(alias)
assert secondEpoch.error == MachineError.None
verify(firstEpoch.value, expected)
expected[128].bytes[100] = 77
verify(secondEpoch.value, expected)

var invalid = @[replacements[0], replacements[0]]
assert withReplacedPages(original, invalid).error == MachineError.UnsortedPages
invalid = @[replacements[2], replacements[0]]
assert withReplacedPages(original, invalid).error == MachineError.UnsortedPages
invalid = @[PageImage(index: PageIndex(999), access: PageAccess.ReadWrite)]
assert withReplacedPages(original, invalid).error == MachineError.InvalidRange
invalid = @[PageImage(index: PageIndex(16), access: PageAccess.ReadOnly)]
assert withReplacedPages(original, invalid).error == MachineError.InvalidRange
invalid = @[PageImage(index: PageIndex(0x100000), access: PageAccess.ReadWrite)]
assert withReplacedPages(original, invalid).error == MachineError.InvalidPage
var output = default(array[4096, byte])
for offset in 0..<4096: output[offset] = 0x5a
assert copyMemoryPage(original, MemoryPageSlot(129), output).error == MachineError.InvalidRange
for value in output: assert value == 0x5a
assert memoryPageCount(captureMemory([], PageLimit(0)).value).error == MachineError.None
assert memoryPageCount(default(Memory)).error == MachineError.InvalidOwner
releaseCycle()
let occupiedBefore = getOccupiedMem()
for cycle in 0..<1000: releaseCycle()
let occupiedAfter = getOccupiedMem()
assert occupiedBefore == occupiedAfter
recordArcRelease("pvm_memory_directory", 1000, occupiedBefore, occupiedAfter)
echo "ARC_RELEASE cycles=1000 unchanged"
echo "PVM directory snapshot boundaries passed"
