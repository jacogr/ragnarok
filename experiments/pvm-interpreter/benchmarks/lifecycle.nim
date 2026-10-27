# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Frozen full-state benchmark with the same decoded-fact/reset boundary as the historical local control.
import std/[assertions, syncio, envvars]
import ../src/pvm/[program, machine, gas, experimental]
import ../src/pvm/step as oracle
proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}
proc word(data: string, at, width: int): uint64 =
  ## All local fixture words are bounded before shifts or narrowing.
  assert at >= 0 and width >= 1 and width <= 8 and at <= data.len-width
  result = 0
  for i in 0..<width: result = result or (uint64(byte(data[at+i])) shl (8*i))
proc local(path: string): string =
  ## A fixture I/O refusal aborts before any valid result row.
  try: result = readFile(path)
  except: quit 2
if getEnv("RAGNAROK_PVM_SIEVE_ASSERT_PROBE") == "1":
  # Linux comparison proves optimized assertion checks remain present before accepting timings.
  assert false, "pvm experimental assertion control"
let guest = getEnv("RAGNAROK_PVM_GUEST")
let data = local(getEnv("RAGNAROK_PVM_SIEVE_INPUT"))
let expected = local(getEnv("RAGNAROK_PVM_SIEVE_EXPECTED"))
assert data.len >= 136 and data[0..7] == "PVMSIV01" and expected.len >= 120 and expected[0..7] == "PVMSIE01"
let wireSize = int(word(data, 8, 4))
let pages = int(word(data, 20, 4))
assert pages > 0 and pages <= 4096 and wireSize > 0 and wireSize <= 4194304 and data.len ==
    136+wireSize+pages*4101
var wire = newSeq[byte](wireSize)
for i in 0..<wireSize: wire[i] = byte(data[136+i])
let decoded = decodeJamProgram(wire, CodeAddress(word(data, 12, 4)), ProgramByteLimit(4194304),
    JumpCountLimit(1048576))
assert decoded.error == ProgramError.None
var info = MachineInfo(pc: CodeAddress(word(data, 12, 4)), gas: MachineGas(word(data, 24, 8)),
    registers: default(RegisterFile), blockCharged: false)
for i in 0..<13: info.registers[i] = RegisterValue(word(data, 32+i*8, 8))
var images: seq[PageImage] = @[]
var cursor = 136+wireSize
for page in 0..<pages:
  let permission = byte(data[cursor+4])
  assert permission in [1'u8, 2'u8]
  var image = PageImage(index: PageIndex(uint32(word(data, cursor, 4))), access: (if permission ==
      1: PageAccess.ReadOnly else: PageAccess.ReadWrite), bytes: default(array[4096, byte]))
  for at in 0..<4096: image.bytes[at] = byte(data[cursor+5+at])
  images.add(image)
  cursor+=4101
let beforePlan = cpuNanoseconds()
let plan = newFlatPlan(decoded.value, GasCycleLimit(1000000))
let planNs = cpuNanoseconds()-beforePlan
let beforeFrame = cpuNanoseconds()
var frame = newFlatFrame(plan, images, info)
let frameNs = cpuNanoseconds()-beforeFrame
echo "PHASE_PREPARE,", guest, ",", planNs, ",", frameNs
let samples = if getEnv("RAGNAROK_PVM_SIEVE_SAMPLES") == "13": 13 elif getEnv(
    "RAGNAROK_PVM_SIEVE_SAMPLES") == "4": 4 else: 1
for sample in 0..<samples:
  let beforeReset = cpuNanoseconds()
  resetFlatFrame(frame, info)
  let before = cpuNanoseconds()
  runFlat(frame, 1000000000)
  let afterExecution = cpuNanoseconds()
  let published = flatMemorySnapshot(frame)
  let captured = captureMachine(decoded.value, published, frame.info)
  let afterPublication = cpuNanoseconds()
  assert captured.error == MachineError.None
  let finalMemory = memoryOf(captured.value).value
  for page in 0..<images.len:
    # Publication is an independent immutable full-state observation, not the frame's private checker.
    let actual = pageImage(finalMemory, images[page].index)
    assert actual.error == MachineError.None
    let image = actual.value
    assert image.access == images[page].access
    for at in 0..<4096: assert image.bytes[at] == byte(expected[120+page*4096+at])
  let elapsed = afterExecution-before
  assert frame.reason == oracle.StepError.None and frame.exit == oracle.StepExit.Halt
  assert uint64(frame.info.pc) == 0 and frame.info.blockCharged and uint64(frame.info.gasDeficit) == 0
  assert uint64(frame.info.gas) == word(expected, 8, 8)
  for i in 0..<13: assert uint64(frame.info.registers[i]) == word(expected, 16+i*8, 8)
  checkFlatReference(frame, expected)
  echo "PHASE,", guest, ",", sample, ",", before-beforeReset, ",", elapsed, ",",
      afterPublication-afterExecution, ",", afterPublication-beforeReset
  echo "PHASE_CACHE,", guest, ",", sample, ",", flatNodes(frame), ",", flatPreparationUnits(frame),
      ",", 1000000000'u64-frame.remaining
