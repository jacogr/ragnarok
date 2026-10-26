# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Full 139-opcode, alias, gas and exit matrix against the unchanged independent interpreter.
import std/[assertions, syncio]
import ../src/codec/natural
import ../src/pvm/[program, machine, gas, step, experimental]
proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Test framing uses the independent natural codec without borrowing program storage.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len:
    # Only the explicitly encoded prefix belongs to the output.
    bytes.add(encoded.bytes[index])

proc owner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): Program =
  ## Explicit instruction boundaries support long blocks and saturated operands without a production assembler.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    # Caller-provided operand bytes never become instruction boundaries.
    starts.add(code.len)
    for value in part: code.add(value)
  var bytes: seq[byte] = @[]
  appendNatural(bytes, uint64(jumps.len))
  bytes.add(if jumps.len == 0: 0'u8 else: 4'u8)
  appendNatural(bytes, uint64(code.len))
  for target in jumps:
    # Fixed four-byte table entries are independent of operand decoding and may deliberately name invalid code targets.
    for shift in 0..<4: bytes.add(byte((uint64(target) shr (shift*8)) and 255))
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len+7) div 8)
  for start in starts:
    # Mark the original opcode positions only.
    mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(65536),
      JumpCountLimit(1024))
  assert decoded.error == ProgramError.None
  decoded.value

proc sameCpu(left, right: MachineInfo) =
  ## All copied CPU fields participate, including the prepaid-block state and reserved gas deficit.
  assert uint64(left.pc) == uint64(right.pc)
  assert uint64(left.gas) == uint64(right.gas)
  assert uint64(left.gasDeficit) == uint64(right.gasDeficit)
  assert left.blockCharged == right.blockCharged
  for index in 0..<13:
    # Compare every register, including operands intentionally aliased by a witness.
    assert uint64(left.registers[index]) == uint64(right.registers[index])

proc memory(): Memory =
  ## Distinct nonzero bytes expose clobbering and partial cross-page writes.
  var pages = default(array[2, PageImage])
  for index in 0..<2:
    pages[index] = PageImage(index: PageIndex(uint32(16+index)),
        access: PageAccess.ReadWrite)
    for at in 0..<4096:
      pages[index].bytes[at] = byte((at*17+index*31+3) mod 256)
  captureMemory(pages, PageLimit(2)).value


proc cache(source: Program): FlatPlan =
  ## Program facts and prices are sealed once; executable stream and input memory remain frame-local.
  newFlatPlan(source, GasCycleLimit(100000))

proc same(actual: FlatFrame, expected: StepResult) =
  ## Failed local runs expose no successful comparison state; every genuine exit checks all selected metadata and mapped bytes.
  assert actual.reason == expected.error
  if expected.error == StepError.None:
    let wanted = expected.value
    assert actual.exit == wanted.exit
    if wanted.exit == StepExit.Fault: assert uint32(actual.faultPage) == uint32(wanted.faultPage)
    if wanted.exit == StepExit.Host: assert uint64(actual.hostCall) == uint64(wanted.hostCall)
    sameCpu(actual.info, machineInfo(wanted.machine).value)
    let memory = flatMemorySnapshot(actual)
    for page in [16'u32, 17'u32]:
      let a = pageImage(memory, PageIndex(page))
      let b = pageImage(memoryOf(wanted.machine).value, PageIndex(page))
      assert a.error == b.error
      if a.error == MachineError.None:
        let ai = a.value
        let bi = b.value
        assert ai.access == bi.access and ai.bytes == bi.bytes
  checkFlatSource(actual)

proc compare(input: Machine, prepared: FlatPlan, steps, cycles: uint64) =
  ## A fresh and reused handler stream see the same original registers and private input reset on each call.
  let info = machineInfo(input).value
  let mem = memoryOf(input).value
  let pages = [pageImage(mem, PageIndex(16)).value, pageImage(mem, PageIndex(17)).value]
  let expected = execute(input, ExecutionStepLimit(steps), GasCycleLimit(cycles))
  var frame = newFlatFrame(prepared, pages, info)
  for repeat in 0..<2:
    resetFlatFrame(frame, info)
    runFlat(frame, steps)
    same(frame, expected)
    sameCpu(machineInfo(input).value, info)

proc immediate(bytes: var seq[byte], value: uint64) =
  for shift in 0..<4: bytes.add(byte((value shr (shift*8)) and 255))

proc firstMemoryPart(code: byte, address: uint64): seq[byte] =
  ## Encode actual mapped absolute/indirect operands independently of the production decoder, with a deliberately aliased register1.
  result = @[code]
  if code <= 33:
    # Absolute immediate stores carry two explicitly four-byte immediates.
    result.add(4)
    immediate(result, address)
    immediate(result, 0x89abcdef'u64)
  elif code in {70'u8..73'u8}:
    # Indirect immediate stores select base1 and a four-byte offset followed by four-byte data.
    result.add(65)
    immediate(result, 0)
    immediate(result, 0x89abcdef'u64)
  else:
    # Absolute forms select A1; indirect register forms alias source/destination/base1.
    result.add(if code < 120: 1'u8 else: 17'u8)
    immediate(result, if code < 120: address else: 0'u64)


proc sameMemory(actual, expected: Memory) =
  ## Every mapped byte and permission belongs to a retained immutable root, independent of later frame state.
  for page in [16'u32, 17'u32]:
    let left = pageImage(actual, PageIndex(page))
    let right = pageImage(expected, PageIndex(page))
    assert left.error == MachineError.None and right.error == MachineError.None
    let a = left.value
    let b = right.value
    assert a.access == b.access and a.bytes == b.bytes

proc escapedSnapshot(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo): Memory =
  ## The returned snapshot must own all retained pages after the entire private frame is destroyed.
  var temporary = newFlatFrame(plan, images, info)
  runFlat(temporary, 2)
  flatMemorySnapshot(temporary)

let emptyProgram = owner([@[0'u8]])
let emptyPlan = cache(emptyProgram)
var defaultFrame = newFlatFrame(emptyPlan, [], MachineInfo(gas: MachineGas(1), registers: default(RegisterFile)))
let emptySnapshot = flatMemorySnapshot(defaultFrame)
let emptyPage = pageImage(emptySnapshot, PageIndex(16))
assert emptyPage.error == MachineError.None
assert emptyPage.value.access == PageAccess.Inaccessible

let initialMemory = memory()
var images = [pageImage(initialMemory, PageIndex(16)).value, pageImage(initialMemory, PageIndex(17)).value]
let publicationProgram = owner([firstMemoryPart(62, 65537), @[0'u8]])
let publicationPlan = cache(publicationProgram)
var info = MachineInfo(gas: MachineGas(100), registers: default(RegisterFile))
info.registers[1] = RegisterValue(0x0123456789abcdef'u64)
let input = captureMachine(publicationProgram, initialMemory, info).value
let firstExpected = execute(input, ExecutionStepLimit(2), GasCycleLimit(100000))
assert firstExpected.error == StepError.None
let firstMemory = memoryOf(firstExpected.value.machine).value
var frame = newFlatFrame(publicationPlan, images, info)
let untouched = flatMemorySnapshot(frame)
sameMemory(untouched, initialMemory)
runFlat(frame, 2)
let first = flatMemorySnapshot(frame)
sameMemory(first, firstMemory)
let escaped = escapedSnapshot(publicationPlan, images, info)
sameMemory(escaped, firstMemory)
for epoch in 0..<64:
  # Reset restores original input, but old published roots must retain their earlier bytes forever.
  var nextInfo = info
  nextInfo.registers[1] = RegisterValue(0xfedcba9876543210'u64 xor uint64(epoch))
  resetFlatFrame(frame, nextInfo)
  sameMemory(flatMemorySnapshot(frame), initialMemory)
  runFlat(frame, 2)
  let latest = flatMemorySnapshot(frame)
  let source = captureMachine(publicationProgram, initialMemory, nextInfo).value
  let expected = execute(source, ExecutionStepLimit(2), GasCycleLimit(100000))
  assert expected.error == StepError.None
  sameMemory(latest, memoryOf(expected.value.machine).value)
  sameMemory(first, firstMemory)
  sameMemory(escaped, firstMemory)
  sameMemory(untouched, initialMemory)
  checkFlatSource(frame)
images[0].access = PageAccess.ReadOnly
let remapped = captureMemory(images, PageLimit(2)).value
replaceFlatMemory(frame, images, info)
runFlat(frame, 2)
assert frame.reason == StepError.None and frame.exit == StepExit.Fault
sameMemory(flatMemorySnapshot(frame), remapped)
sameMemory(first, firstMemory)
sameMemory(escaped, firstMemory)
sameMemory(untouched, initialMemory)
echo "PASS publication immutable epochs /64resets / frame destruction / RO replacement / empty memory / full bytes"
