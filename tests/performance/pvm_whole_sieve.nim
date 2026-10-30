# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private gas-free whole-program ARM64 sieve. Full register/memory/source checks stay outside CPU clocks.
## This driver never imports an interpreter or JIT; comparison images are separate executables.
import std/[assertions, syncio, envvars]
import ../../src/pvm/[program, machine]
import ./pvm_whole_image

proc word(data: string, at, width: int): uint64 =
  ## Decode fixed-width fields only within the independently framed fixture's extent.
  assert at >= 0 and width >= 1 and width <= 8 and at <= data.len - width
  result = 0
  for i in 0..<width: result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc count(limit: uint64): uint64 =
  ## Independent known prime counts supplement the complete external register/memory oracle.
  case limit
  of 100: 25'u64
  of 1000: 168'u64
  of 10000: 1229'u64
  of 100000: 9592'u64
  of 1000000: 78498'u64
  of 10000000: 664579'u64
  else:
    assert false, "unknown sieve size"
    0'u64

proc checkMemory(memory: Memory, indices: seq[PageIndex], access: seq[PageAccess], expected: string,
    offset: int): void =
  ## Compare every initialized/mapped byte; a matching prime count alone is insufficient.
  assert expected.len == offset + indices.len * 4096
  for page in 0..<indices.len:
    let image = pageImage(memory, indices[page]).value
    assert image.access == access[page]
    for i in 0..<4096: assert image.bytes[i] == byte(expected[offset + page * 4096 + i])

let inputCpuStart = cpuNs()
let inputWallStart = wallNs()
assert getEnv("RAGNAROK_PVM_GUEST") in ["", "sieve"]
if getEnv("RAGNAROK_PVM_SIEVE_ASSERT_PROBE") == "1":
  assert false, "whole-image sieve assertion control"
var data = ""
var expected = ""
try:
  data = readFile(getEnv("RAGNAROK_PVM_SIEVE_INPUT"))
  expected = readFile(getEnv("RAGNAROK_PVM_SIEVE_EXPECTED"))
except:
  quit 2
assert data.len >= 136 and data[0..7] == "PVMSIV01"
assert expected.len >= 120 and expected[0..7] == "PVMSIE01"
let wireSize = int(word(data, 8, 4))
let entry = word(data, 12, 4)
let limit = word(data, 16, 4)
discard count(limit) # Reject a foreign family/size before an expensive execution or policy allocation.
let pageCount = int(word(data, 20, 4))
assert wireSize > 0 and wireSize <= 4 * 1024 * 1024 and pageCount > 0 and pageCount <= 4096
assert data.len == 136 + wireSize + pageCount * 4101
var info = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(word(data, 24, 8)),
  registers: default(RegisterFile), blockCharged: false)
for i in 0..<13: info.registers[i] = RegisterValue(word(data, 32 + i * 8, 8))
var wire = newSeq[byte](wireSize)
for i in 0..<wireSize: wire[i] = byte(data[136 + i])
let decoded = decodeJamProgram(wire, CodeAddress(entry), ProgramByteLimit(4 * 1024 * 1024),
  JumpCountLimit(1024 * 1024))
assert decoded.error == ProgramError.None, "sieve program decoding"
let owner = decoded.value
var images: seq[PageImage] = @[]
var indices: seq[PageIndex] = @[]
var access: seq[PageAccess] = @[]
var cursor = 136 + wireSize
var originalBytes = ""
for page in 0..<pageCount:
  let index = PageIndex(uint32(word(data, cursor, 4)))
  let permission = byte(data[cursor + 4])
  assert permission in [1'u8, 2'u8]
  var image = PageImage(index: index,
    access: (if permission == 1: PageAccess.ReadOnly else: PageAccess.ReadWrite),
    bytes: default(array[4096, byte]))
  for i in 0..<4096:
    image.bytes[i] = byte(data[cursor + 5 + i])
    originalBytes.add(data[cursor + 5 + i])
  images.add(image)
  indices.add(index)
  access.add(image.access)
  cursor += 4101
let captured = captureMemory(images, PageLimit(uint32(pageCount)))
assert captured.error == MachineError.None
let memory = captured.value

echo "WHOLE_INPUT_PREPARE,", cpuNs()-inputCpuStart, ",", wallNs()-inputWallStart
var image = default(WholeImage)
var diagnostic = ""
let compileCpu = cpuNs()
let compileWall = wallNs()
assert compileWhole(owner, info.pc, image, diagnostic), diagnostic
let compileWallElapsed = wallNs()-compileWall
let compileCpuElapsed = cpuNs()-compileCpu
echo "WHOLE_IMAGE,", image.codeBytes, ",", image.instructions, ",", compileCpuElapsed, ",", compileWallElapsed
let requestedSamples = getEnv("RAGNAROK_PVM_SIEVE_SAMPLES")
assert requestedSamples in ["", "1", "2", "3", "13"]
let samples = if requestedSamples == "1": 1 elif requestedSamples == "3": 3 elif requestedSamples ==
    "13": 13 else: 2
echo "WHOLE_GAS_DISABLED,1"
for sample in 0..<samples:
  # Every repeat reuses immutable code and restores the same real guest memory/CPU source.
  let restoreCpu = cpuNs()
  let restoreWall = wallNs()
  let madeWriter = newScalarMemoryWriter(memory)
  assert madeWriter.error == MachineError.None
  let writer = madeWriter.value
  echo "WHOLE_RESTORE,", sample, ",", cpuNs()-restoreCpu, ",", wallNs()-restoreWall
  let startedCpu = cpuNs()
  let startedWall = wallNs()
  let done = invoke(image, writer, info.registers)
  let elapsedWall = wallNs()-startedWall
  let elapsedCpu = cpuNs()-startedCpu
  echo "WHOLE_EXIT,", sample, ",", done.status, ",", done.pc, ",", done.exits, ",", done.loads, ",",
      done.stores,
    ",", elapsedCpu, ",", elapsedWall
  assert done.status == 1 and done.pc == 0 and done.exits == 1
  assert done.registers[7] == count(limit)
  for i in 0..<13: assert done.registers[i] == word(expected, 16+i*8, 8), "whole register " & $i
  let publishCpu = cpuNs()
  let publishWall = wallNs()
  let frozen = snapshotMemory(writer)
  echo "WHOLE_PUBLICATION,", sample, ",", cpuNs()-publishCpu, ",", wallNs()-publishWall
  assert frozen.error == MachineError.None
  assert uint32(memoryPageCount(frozen.value).value) == uint32(pageCount)
  checkMemory(frozen.value, indices, access, expected, 120)
  checkMemory(memory, indices, access, originalBytes, 0)
  assert programBytes(owner).value == wire, "whole source changed"
let retireCpu = cpuNs()
let retireWall = wallNs()
release(image)
echo "WHOLE_IMAGE_RETIRE,", cpuNs()-retireCpu, ",", wallNs()-retireWall
assert allocationCounts() == [1'u64, 1'u64]
echo "WHOLE_PASS,", limit
