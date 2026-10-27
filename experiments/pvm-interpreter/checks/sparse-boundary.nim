# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Fragmented permission regions, exact whole-range faults, host continuation and immutable aliases.
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


proc same(frame: FlatFrame, wanted: StepResult, images: openArray[PageImage]) =
  ## Compare every mapped byte/access tag and complete CPU/exit metadata after private execution.
  assert frame.reason == wanted.error
  if wanted.error == StepError.None:
    let value = wanted.value
    assert frame.exit == value.exit
    sameCpu(frame.info, machineInfo(value.machine).value)
    if value.exit == StepExit.Fault: assert uint32(frame.faultPage) == uint32(value.faultPage)
    if value.exit == StepExit.Host: assert uint64(frame.hostCall) == uint64(value.hostCall)
    let memory = flatMemorySnapshot(frame)
    for i in 0..<images.len:
      let a = pageImage(memory, images[i].index).value
      let b = pageImage(memoryOf(value.machine).value, images[i].index).value
      assert a.access == b.access and a.bytes == b.bytes
  checkFlatSource(frame)

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


proc samePages(actual, expected: Memory, images: openArray[PageImage]) =
  ## Complete immutable bytes and permissions reveal both missing dirty marks and partial failed writes.
  for i in 0..<images.len:
    let a = pageImage(actual, images[i].index).value
    let b = pageImage(expected, images[i].index).value
    assert a.access == b.access and a.bytes == b.bytes, "page bytes mismatch"
var cases = 0
for code in [30'u8, 31, 32, 33]:
  for address in [69631'u64, 262143'u64, 262144'u64, 4294967294'u64]:
    for access in [PageAccess.ReadWrite, PageAccess.ReadOnly, PageAccess.Inaccessible]:
      echo "CASE,", code, ",", address, ",", access
      var images: seq[PageImage] = @[]
      for index in [16'u32, 17'u32, 63'u32, 64'u32, 1048575'u32]:
        var image = PageImage(index: PageIndex(index), access: PageAccess.ReadWrite)
        if index in [17'u32, 64'u32, 1048575'u32]: image.access = access
        for i in 0..<4096: image.bytes[i] = byte((i*7+int(index)) mod 251)
        images.add(image)
      let memory = captureMemory(images, PageLimit(5)).value
      let program = owner([firstMemoryPart(code, address), @[10'u8, 1'u8], @[0'u8]])
      let plan = newFlatPlan(program, GasCycleLimit(100000))
      let info = MachineInfo(gas: MachineGas(1000), registers: default(RegisterFile))
      let source = captureMachine(program, memory, info).value
      let expected = execute(source, ExecutionStepLimit(2), GasCycleLimit(100000))
      assert expected.error == StepError.None, "reference error"
      var frame = newFlatFrame(plan, images, info)
      runFlat(frame, 1)
      let held = flatMemorySnapshot(frame)
      samePages(held, memoryOf(expected.value.machine).value, images)
      if frame.reason == StepError.StepLimitExceeded:
        # The next run must preserve dirty marks across a local source-budget refusal.
        runFlat(frame, 1)
      assert frame.reason == StepError.None and frame.exit == expected.value.exit, "continuation exit"
      sameCpu(frame.info, machineInfo(expected.value.machine).value)
      if frame.exit == StepExit.Host:
        let observed = observeFlatHostMemory(frame)
        let state = frame.info
        assert resumeFlatHostMemory(frame, default(Memory), state.gas, state.registers) ==
            StepError.InvalidHostResponse
        samePages(flatMemorySnapshot(frame), observed, images)
        assert resumeFlatHostMemory(frame, observed, state.gas, state.registers) == StepError.None
        samePages(flatMemorySnapshot(frame), observed, images)
      samePages(held, memoryOf(expected.value.machine).value, images)
      inc cases
# A write restored to its original bytes must publish the exact original state across budget stops.
proc byteStore(address, value: uint64): seq[byte] =
  ## Two independently encoded stores expose a flag incorrectly cleared merely by observing memory.
  result = @[30'u8, 4'u8]
  immediate(result, address)
  immediate(result, value)
let images = [PageImage(index: PageIndex(63), access: PageAccess.ReadWrite)]
let initial = captureMemory(images, PageLimit(1)).value
let restoreProgram = owner([byteStore(258049, 0xaa), byteStore(258049, 0), @[10'u8, 1'u8], @[0'u8]])
let info = MachineInfo(gas: MachineGas(1000), registers: default(RegisterFile))
var frame = newFlatFrame(newFlatPlan(restoreProgram, GasCycleLimit(100000)), images, info)
runFlat(frame, 1)
echo "RESTORE1,", frame.reason, ",", frame.exit, ",", uint64(frame.info.pc)
let beforeRestore = flatMemorySnapshot(frame)
echo "BYTE1,", pageImage(beforeRestore, PageIndex(63)).value.bytes[1]
assert pageImage(beforeRestore, PageIndex(63)).value.bytes[1] == 0xaa, "restore retained byte"
runFlat(frame, 1)
echo "RESTORE2,", frame.reason, ",", frame.exit, ",", uint64(frame.info.pc)
echo "BYTE2,", pageImage(flatMemorySnapshot(frame), PageIndex(63)).value.bytes[1]
samePages(flatMemorySnapshot(frame), initial, images)
assert pageImage(beforeRestore, PageIndex(63)).value.bytes[1] == 0xaa, "restore retained byte"
resetFlatFrame(frame, info)
samePages(flatMemorySnapshot(frame), initial, images)
echo "PASS sparse publication /", cases, "/ widths1-8 / bitmap-word and top-address boundaries / failed stores / budget continuation / restored bytes / old snapshots"
