# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute the exact linked upstream sieve supplied to PolkaVM; compare complete reference outputs.
import std/[assertions, syncio, monotimes, envvars]
import ../../src/pvm/[program, machine, gas]
import ../../src/pvm/step as reference

proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}
  ## Record CPU time alongside the elapsed metric also emitted by the reference harness.

proc word(data: string, at, width: int): uint64 =
  ## Decode fixed-width fields only within the independently framed fixture's extent.
  assert at >= 0 and width >= 1 and width <= 8 and at <= data.len - width
  result = 0
  for i in 0..<width: result = result or (uint64(byte(data[at + i])) shl (8 * i))

proc count(limit: uint64): uint64 =
  ## Known prime counts are independent of the two timed interpreters.
  case limit
  of 100: 25'u64
  of 1000: 168'u64
  of 10000: 1229'u64
  of 100000: 9592'u64
  of 1000000: 78498'u64
  of 10000000: 664579'u64
  else:
    assert false
    0'u64

proc checkMemory(memory: Memory, indices: seq[PageIndex], access: seq[PageAccess], expected: string,
    offset: int): void =
  ## Compare every initialized/mapped byte; a matching prime count alone is insufficient.
  assert expected.len == offset + indices.len * 4096
  for page in 0..<indices.len:
    let image = pageImage(memory, indices[page]).value
    assert image.access == access[page]
    for i in 0..<4096: assert image.bytes[i] == byte(expected[offset + page * 4096 + i])

proc check(machine: Machine, indices: seq[PageIndex], access: seq[PageAccess], expected: string,
    limit: uint64) =
  ## Validate terminal CPU state, exact gas, all registers and all mapped memory outside timing.
  let cpu = machineInfo(machine).value
  assert uint64(cpu.pc) == 0 and cpu.blockCharged and uint64(cpu.gasDeficit) == 0
  assert uint64(cpu.gas) == word(expected, 8, 8)
  for i in 0..<13: assert uint64(cpu.registers[i]) == word(expected, 16 + i * 8, 8)
  assert uint64(cpu.registers[7]) == count(limit)
  checkMemory(memoryOf(machine).value, indices, access, expected, 120)

if getEnv("RAGNAROK_PVM_SIEVE_ASSERT_PROBE") == "1":
  assert false, "pvm sieve native assertion control"
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
let source = captureMachine(owner, memory, info).value
let engine = "ragnarok"
let requestedSamples = getEnv("RAGNAROK_PVM_SIEVE_SAMPLES")
assert requestedSamples in ["1", "13"]
let samples = if requestedSamples == "1": 1 else: 13
for sample in 0..<samples:
  # Program/memory/ABI setup is outside execution timing in both interpreters.
  let wallStart = getMonoTime().ticks
  let cpuStart = cpuNanoseconds()
  let done = reference.execute(source, reference.ExecutionStepLimit(1000000000), GasCycleLimit(1000000))
  let cpuElapsed = cpuNanoseconds() - cpuStart
  let elapsed = getMonoTime().ticks - wallStart
  assert done.error == reference.StepError.None, "current sieve execution"
  assert done.value.exit == reference.StepExit.Halt
  check(done.value.machine, indices, access, expected, limit)
  echo "SIEVE,", engine, ",", limit, ",", sample, ",", elapsed, ",", cpuElapsed
  checkMemory(memory, indices, access, originalBytes, 0)
  let original = machineInfo(source).value
  assert uint64(original.pc) == entry and uint64(original.gas) == uint64(info.gas)
  assert not original.blockCharged
  for i in 0..<13: assert uint64(original.registers[i]) == uint64(info.registers[i])
