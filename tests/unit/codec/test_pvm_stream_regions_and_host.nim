# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Fragmented permission regions, exact whole-range faults, host continuation and immutable aliases.
import std/assertions
import std/syncio
import ../../../src/pvm/internal/handler_stream as pvm_handler_stream
import ../../../src/codec/natural as codec_natural
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
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

var images = [PageImage(index: PageIndex(16), access: PageAccess.ReadWrite),
  PageImage(index: PageIndex(17), access: PageAccess.ReadOnly),
  PageImage(index: PageIndex(32), access: PageAccess.ReadWrite),
  PageImage(index: PageIndex(34), access: PageAccess.Inaccessible),
  PageImage(index: PageIndex(36), access: PageAccess.ReadOnly),
  PageImage(index: PageIndex(38), access: PageAccess.ReadWrite),
  PageImage(index: PageIndex(40), access: PageAccess.ReadOnly),
  PageImage(index: PageIndex(1048575), access: PageAccess.ReadWrite)]
for page in 0..<images.len:
  for at in 0..<4096: images[page].bytes[at] = byte((at*17+page*31) mod 251)
let captured = captureMemory(images, PageLimit(8)).value
proc immediate(part: var seq[byte], value: uint64) =
  ## Explicit little-endian operands make the fixture independent of the production decoder.
  for i in 0..<4: part.add(byte((value shr (8*i)) and 255'u64))
for code in [30'u8, 31, 32, 33, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 70, 71, 72, 73, 120,
    121, 122, 123, 124, 125, 126, 127, 128, 129, 130]:
  for address in [0'u64, 65536, 69629, 73725, 131072, 143359, 147455, 155648, 163840,
      0xfffffff8'u64, 0xfffffffe'u64, 0xffffffff'u64, 0x100010003'u64]:
    var part = @[code]
    if code <= 33:
      part.add(4)
      immediate(part, address)
      immediate(part, 0x89abcdef'u64)
    elif code in {70'u8..73'u8}:
      part.add(65)
      immediate(part, 0)
      immediate(part, 0x89abcdef'u64)
    else:
      part.add(if code < 120: 1'u8 else: 17'u8)
      immediate(part, if code < 120: address else: 0'u64)
    let program = owner([part, @[0'u8]])
    let plan = newFlatPlan(program, GasCycleLimit(100000))
    var regs = default(RegisterFile)
    regs[1] = RegisterValue(address)
    let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000), registers: regs,
        blockCharged: false)
    let source = captureMachine(program, captured, info).value
    let wanted = execute(source, ExecutionStepLimit(5), GasCycleLimit(100000))
    var frame = newFlatFrame(plan, images, info)
    runFlat(frame, 5)
    same(frame, wanted, images)
echo "PASS all 30 memory opcodes / fragmented RO-RW-inaccessible regions / wrap and fault precedence"

let hostProgram = owner([@[10'u8, 1'u8], @[2'u8], @[10'u8, 1'u8], @[50'u8, 0'u8]])
let hostPlan = newFlatPlan(hostProgram, GasCycleLimit(100000))
var regs = default(RegisterFile)
regs[0] = RegisterValue(0xffff0000'u64)
let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000), registers: regs,
    blockCharged: false)
var source = captureMachine(hostProgram, captured, info).value
var frame = newFlatFrame(hostPlan, images, info)
for call in 0..<2:
  let stopped = execute(source, ExecutionStepLimit(10), GasCycleLimit(100000))
  assert stopped.error == StepError.None and stopped.value.exit == StepExit.Host
  runFlat(frame, 10)
  same(frame, stopped, images)
  var posterior = machineInfo(stopped.value.machine).value.registers
  posterior[7] = RegisterValue(uint64(call+1))
  images[0].bytes[call] = byte(100+call)
  images[1].access = if call == 0: PageAccess.ReadWrite else: PageAccess.ReadOnly
  let memory = captureMemory(images, PageLimit(8)).value
  let state = machineInfo(stopped.value.machine).value
  let response = HostResponse(action: HostAction.Continue, gas: state.gas, registers: posterior,
      memory: memory)
  let applied = applyHostResponse(stopped.value, response)
  assert applied.error == StepError.None
  source = applied.value.machine
  resumeFlatHost(frame, images, state.gas, posterior)
  sameCpu(frame.info, machineInfo(source).value)
let done = execute(source, ExecutionStepLimit(10), GasCycleLimit(100000))
runFlat(frame, 10)
same(frame, done, images)
echo "PASS adjacent host reentry / paid suffix / decoder successor / changed memory permissions"

# An early fault restores the unused budget barrier before repaired memory and cached code reenter the same prepaid block.
let faultProgram = owner([@[58'u8, 1'u8, 0'u8, 0'u8, 1'u8, 0'u8], @[149'u8, 0x77'u8, 1'u8], @[0'u8]])
let faultPlan = newFlatPlan(faultProgram, GasCycleLimit(100000))
let missing = captureMemory([], PageLimit(8)).value
let faultInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(
    RegisterFile), blockCharged: false)
let faultSource = captureMachine(faultProgram, missing, faultInfo).value
let wantedFault = execute(faultSource, ExecutionStepLimit(2), GasCycleLimit(100000))
var repairing = newFlatFrame(faultPlan, [], faultInfo)
runFlat(repairing, 2)
same(repairing, wantedFault, [])
assert repairing.exit == StepExit.Fault and repairing.remaining == 1
let paid = repairing.info
let repairedMemory = captureMemory(images, PageLimit(8)).value
let repairedSource = captureMachine(faultProgram, repairedMemory, paid).value
replaceFlatMemory(repairing, images, paid)
let wantedRepair = execute(repairedSource, ExecutionStepLimit(5), GasCycleLimit(100000))
runFlat(repairing, 5)
same(repairing, wantedRepair, images)
assert uint64(repairing.info.gas) == uint64(paid.gas)
echo "PASS early fault budget refund / restored barrier / repaired memory without double charge"
