# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Full 139-opcode, alias, gas and exit matrix across direct and public snapshot execution boundaries.
import std/[assertions, syncio]
import ../../../src/pvm/internal/handler_stream
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, gas, step]
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

# A minimal overlapping suffix must never redirect the original stream's quota barrier.
let reuseProgram = owner([@[51'u8, 1'u8, 11'u8], @[51'u8, 2'u8, 22'u8], @[50'u8, 0'u8]])
let reuseMemory = memory()
var reuseInfo = MachineInfo(gas: MachineGas(1000), registers: default(RegisterFile))
reuseInfo.registers[0] = RegisterValue(0xffff0000'u64)
let reuseSource = captureMachine(reuseProgram, reuseMemory, reuseInfo).value
let reuseImages = [pageImage(reuseMemory, PageIndex(16)).value, pageImage(reuseMemory, PageIndex(17)).value]
var reuseFrame = newFlatFrame(cache(reuseProgram), reuseImages, reuseInfo)
runFlat(reuseFrame, 1)
assert reuseFrame.reason == StepError.StepLimitExceeded
runFlat(reuseFrame, 2)
assert reuseFrame.reason == StepError.None and reuseFrame.exit == StepExit.Halt
resetFlatFrame(reuseFrame, reuseInfo)
runFlat(reuseFrame, 2)
if reuseFrame.reason != StepError.StepLimitExceeded:
  echo "ACTIVE_STREAM_REPRO,", reuseFrame.reason, ",", reuseFrame.exit, ",", reuseFrame.remaining
assert reuseFrame.reason == StepError.StepLimitExceeded and reuseFrame.remaining == 0, "active stream cached-suffix quota"
let reuseOne = stepOnce(reuseSource, GasCycleLimit(100000))
assert reuseOne.error == StepError.None and reuseOne.value.exit == StepExit.Continued
let reuseTwo = stepOnce(reuseOne.value.machine, GasCycleLimit(100000))
assert reuseTwo.error == StepError.None and reuseTwo.value.exit == StepExit.Continued
sameCpu(reuseFrame.info, machineInfo(reuseTwo.value.machine).value)
sameMemory(flatMemorySnapshot(reuseFrame), memoryOf(reuseTwo.value.machine).value)
checkFlatSource(reuseFrame)
echo "PASS minimal active-stream quota / partial-resume-reset / independent two-instruction state"

# Descending first-dirty order, duplicate stores and a cross-word page pair must publish sorted complete changes.
const directoryIndices = [16'u32, 17'u32, 63'u32, 64'u32, 1048575'u32]
var directoryImages: seq[PageImage] = @[]
for slot in 0..<directoryIndices.len:
  var image = PageImage(index: PageIndex(directoryIndices[slot]), access: PageAccess.ReadWrite)
  image.bytes[0] = byte(slot+1)
  directoryImages.add(image)
let directorySourceMemory = captureMemory(directoryImages, PageLimit(5)).value
let directoryProgram = owner([firstMemoryPart(30, 4294963205'u64),
  firstMemoryPart(30, 262151), firstMemoryPart(30, 65545), firstMemoryPart(30, 262151),
  firstMemoryPart(33, 262141), firstMemoryPart(30, 69643), @[50'u8, 0'u8]])
var directoryInfo = MachineInfo(gas: MachineGas(1000), registers: default(RegisterFile))
directoryInfo.registers[0] = RegisterValue(0xffff0000'u64)
let directorySource = captureMachine(directoryProgram, directorySourceMemory, directoryInfo).value
let directoryPlan = cache(directoryProgram)
var directoryFrame = newFlatFrame(directoryPlan, directoryImages, directoryInfo)
proc directorySame(actual, expected: Memory) =
  ## Every mapped byte and permission participates, including the top physical page and private extra region.
  for index in directoryIndices:
    let left = pageImage(actual, PageIndex(index))
    let right = pageImage(expected, PageIndex(index))
    assert left.error == MachineError.None and right.error == MachineError.None
    assert left.value.bytes == right.value.bytes and left.value.access == right.value.access
var completeStores = directorySource
for step in 0..<6:
  let next = stepOnce(completeStores, GasCycleLimit(100000))
  assert next.error == StepError.None and next.value.exit == StepExit.Continued, "directory oracle store prefix"
  completeStores = next.value.machine
let completed = execute(directorySource, ExecutionStepLimit(7), GasCycleLimit(100000))
assert completed.error == StepError.None and completed.value.exit == StepExit.Halt, "directory completed source"
var directoryCases = 0
for epoch in 0..<2:
  for budget in 0..6:
    # Each prefix is independently replayed by single-step semantics, then continued without clearing its dirty state.
    var wanted = directorySource
    for step in 0..<budget:
      let next = stepOnce(wanted, GasCycleLimit(100000))
      assert next.error == StepError.None and next.value.exit == StepExit.Continued
      wanted = next.value.machine
    resetFlatFrame(directoryFrame, directoryInfo)
    runFlat(directoryFrame, uint64(budget))
    assert directoryFrame.reason == StepError.StepLimitExceeded and directoryFrame.remaining == 0, "directory prefix source budget"
    sameCpu(directoryFrame.info, machineInfo(wanted).value)
    let heldPrefix = flatMemorySnapshot(directoryFrame)
    directorySame(heldPrefix, memoryOf(wanted).value)
    directorySame(flatMemorySnapshot(directoryFrame), memoryOf(wanted).value)
    if budget < 6:
      runFlat(directoryFrame, uint64(6-budget))
      assert directoryFrame.reason == StepError.StepLimitExceeded
    directorySame(flatMemorySnapshot(directoryFrame), memoryOf(completeStores).value)
    directorySame(heldPrefix, memoryOf(wanted).value)
    runFlat(directoryFrame, 1)
    assert directoryFrame.reason == StepError.None and directoryFrame.exit == StepExit.Halt
    sameCpu(directoryFrame.info, machineInfo(completed.value.machine).value)
    directorySame(flatMemorySnapshot(directoryFrame), memoryOf(completed.value.machine).value)
    directorySame(heldPrefix, memoryOf(wanted).value)
    directorySame(directorySourceMemory, memoryOf(directorySource).value)
    checkFlatSource(directoryFrame)
    inc directoryCases
assert directoryCases == 14
echo "PASS active-stream publication /14prefix-epochs / reverse order / duplicate stores / cross-word and top pages / repeated observations / retained snapshots"


proc cachedStreamPrefixes(program: Program, source: Machine, images: openArray[PageImage],
    steps: int): int =
  ## Reuse one stream through distinct paid suffix entries; every prefix is checked against independent single steps.
  assert steps >= 0 and steps < 1024
  let plan = cache(program)
  let info = machineInfo(source).value
  var expected: seq[Machine] = @[source]
  for step in 0..<steps:
    let next = stepOnce(expected[expected.len-1], GasCycleLimit(100000))
    assert next.error == StepError.None and next.value.exit == StepExit.Continued
    expected.add(next.value.machine)
    assert expected.len == step+2
  let done = execute(source, ExecutionStepLimit(uint64(steps+1)), GasCycleLimit(100000))
  assert done.error == StepError.None and done.value.exit == StepExit.Halt
  var active = newFlatFrame(plan, images, info)
  result = 0
  for epoch in 0..<2:
    for budget in 0..steps:
      resetFlatFrame(active, info)
      runFlat(active, uint64(budget))
      assert active.reason == StepError.StepLimitExceeded and active.remaining == 0, "cached stream prefix quota"
      sameCpu(active.info, machineInfo(expected[budget]).value)
      let held = flatMemorySnapshot(active)
      directorySame(held, memoryOf(expected[budget]).value)
      if budget < steps:
        runFlat(active, uint64(steps-budget))
        assert active.reason == StepError.StepLimitExceeded, "cached stream continued quota"
      directorySame(flatMemorySnapshot(active), memoryOf(expected[steps]).value)
      directorySame(held, memoryOf(expected[budget]).value)
      runFlat(active, 1)
      assert active.reason == StepError.None and active.exit == StepExit.Halt
      sameCpu(active.info, machineInfo(done.value.machine).value)
      directorySame(flatMemorySnapshot(active), memoryOf(done.value.machine).value)
      directorySame(held, memoryOf(expected[budget]).value)
      checkFlatSource(active)
      inc result

var foldedStreamCases = 0
for noops in [1, 2, 7]:
  # Folded gaps share executable coordinates, while each original source instruction retains a distinct quota boundary.
  var parts: seq[seq[byte]] = @[]
  for store in [firstMemoryPart(30, 4294963205'u64), firstMemoryPart(30, 262151),
      firstMemoryPart(30, 65545), firstMemoryPart(30, 262151), firstMemoryPart(33, 262141),
      firstMemoryPart(30, 69643)]:
    for count in 0..<noops: parts.add(@[2'u8])
    parts.add(store)
  parts.add(@[50'u8, 0'u8])
  let program = owner(parts)
  let source = captureMachine(program, directorySourceMemory, directoryInfo).value
  foldedStreamCases+=cachedStreamPrefixes(program, source, directoryImages, 6*(noops+1))
assert foldedStreamCases == 162
echo "PASS active-stream folded boundaries /162prefix-epochs / independent quotas / suffix reuse / immutable observations"
