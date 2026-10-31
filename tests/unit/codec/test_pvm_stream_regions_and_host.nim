# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Fragmented permission regions, exact whole-range faults, host continuation and immutable aliases.
import std/[assertions, syncio]
import ../../../src/pvm/internal/handler_stream
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
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
  checkFlatSource(frame, images)

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

proc checkpointStore(address: uint64, value: uint64, wide: bool = false): seq[byte] =
  ## Literal absolute stores keep the expected page bytes independent of production execution.
  result = @[if wide: 31'u8 else: 30'u8, 4'u8]
  immediate(result, address)
  immediate(result, value)

proc expectPages(memory: Memory, expected: openArray[PageImage]) =
  ## Compare every byte and permission, including untouched pages and retained earlier snapshots.
  assert uint32(memoryPageCount(memory).value) == uint32(expected.len)
  for image in expected:
    let actual = pageImage(memory, image.index).value
    assert uint32(actual.index) == uint32(image.index) and actual.access == image.access and
        actual.bytes == image.bytes

proc initializedRegionBytes() =
  ## Guest loads visit every byte; clean snapshot reconstruction must not hide omitted resident copies.
  let indices = [16'u32, 17, 32, 33, 36, 38, 40, 44, 1048575]
  let permissions = [PageAccess.ReadOnly, PageAccess.ReadOnly, PageAccess.ReadWrite,
    PageAccess.ReadWrite, PageAccess.Inaccessible, PageAccess.ReadOnly, PageAccess.ReadWrite,
    PageAccess.ReadOnly, PageAccess.ReadWrite]
  var parts: seq[seq[byte]] = @[]
  for page in 0..<indices.len:
    # Each loop visits all guest-readable page bytes; the reserved final address retains its scalar refusal.
    if permissions[page] == PageAccess.Inaccessible: continue
    let address = uint64(indices[page])*4096
    let ending = address+4096-(if indices[page] == 1048575: 1'u64 else: 0'u64)
    for boundary in [address, ending]:
      # Full-width constants avoid sign-extending the final page's address and end pointer.
      var part = @[20'u8, byte(if boundary == address: 1 else: 3)]
      for shift in 0..<8: part.add(byte((boundary shr (shift*8)) and 255))
      parts.add(part)
    parts.add(@[40'u8, 2'u8]) # A genuine block boundary makes the loop backedge legal.
    parts.add(@[124'u8, 0x12'u8]) # load_ind_u8 r2, [r1].
    parts.add(@[150'u8, 0'u8, 1'u8, 1'u8]) # mul_imm_64 r0, r0, 257.
    parts.add(@[200'u8, 0x20'u8, 0'u8]) # add_64 r0, r0, r2.
    parts.add(@[149'u8, 0x11'u8, 1'u8]) # add_imm_64 r1, r1, 1.
    parts.add(@[171'u8, 0x31'u8, 0xf4'u8]) # branch_ne r1, r3, -12 to the load.
  # Dirtying the top page makes snapshot publication expose its otherwise unreadable final byte too.
  var store = @[59'u8, 2'u8]
  immediate(store, 0xfffff000'u64)
  parts.add(store)
  parts.add(@[10'u8])
  parts.add(@[0'u8])
  let program = owner(parts)
  let prepared = newFlatPlan(program, GasCycleLimit(1000000))
  # Independent modulo-2^64 polynomial hashes bind byte values and order across eight accessible pages.
  let checksums = [17833110151408994656'u64, 9889834429281563842'u64]
  for generation in 0..<checksums.len:
    # Changed fresh inputs with a reused code owner must replace every resident byte on each invocation.
    var pages = newSeq[PageImage](indices.len)
    for page in 0..<pages.len:
      pages[page] = PageImage(index: PageIndex(indices[page]), access: permissions[page])
      for at in 0..<4096:
        pages[page].bytes[at] = byte((at*17+page*31+generation*19) mod 251)
    let input = MachineInfo(gas: MachineGas(2000000), registers: default(RegisterFile))
    var current = newFlatFrame(prepared, pages, input)
    runFlat(current, 200000)
    assert current.reason == StepError.None and current.exit == StepExit.Host
    assert uint64(current.info.registers[0]) == checksums[generation]
    let top = pageImage(flatMemorySnapshot(current), PageIndex(1048575)).value
    assert top.bytes[4095] == pages[pages.len-1].bytes[4095]
    checkFlatSource(current, pages)

initializedRegionBytes()
echo "PASS complete resident initialization / every guest byte / adjacent and extra RO-RW / top page / fresh inputs"



proc checkpointEpoch(dense: bool) =
  ## Unchanged, repeated, reversed, cross-word and dense writes survive observation, resume and reset.
  var initial = newSeq[PageImage](257)
  for page in 0..<initial.len:
    # The final isolated page exercises the highest bitmap word without allocating guest address holes.
    initial[page] = PageImage(index: PageIndex(if page == 256: 1048575'u32 else: uint32(16+page)),
      access: PageAccess.ReadWrite)
  var expected = newSeq[PageImage](initial.len)
  for page in 0..<initial.len: expected[page] = initial[page]
  var parts = @[@[10'u8]]
  let count = if dense: 256 else: 1
  for descending in 0..<count:
    # Reverse visit order must still publish strictly sorted replacement pages.
    let page = count-descending-1
    parts.add(checkpointStore(uint64(16+page)*4096, 91))
    expected[page].bytes[0] = 91
  parts.add(checkpointStore(0xfffff000'u64, 73))
  expected[256].bytes[0] = 73
  parts.add(checkpointStore(262143, 0x1234, true))
  expected[47].bytes[4095] = 0x34
  expected[48].bytes[0] = 0x12
  parts.add(checkpointStore(65537, 42))
  parts.add(checkpointStore(65537, 0))
  parts.add(@[10'u8])
  parts.add(checkpointStore(65536, 17))
  parts.add(@[10'u8])
  parts.add(@[0'u8])
  let program = owner(parts)
  let prepared = newFlatPlan(program, GasCycleLimit(100000))
  let input = MachineInfo(gas: MachineGas(100000))
  var current = newFlatFrame(prepared, initial, input)
  runFlat(current, 1000)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  let untouched = observeFlatHostMemory(current)
  expectPages(untouched, initial)
  let gas = current.info.gas
  let registers = current.info.registers
  assert resumeFlatHostMemory(current, untouched, gas, registers) == StepError.None
  runFlat(current, 1000)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  let first = observeFlatHostMemory(current)
  expectPages(first, expected)
  expectPages(observeFlatHostMemory(current), expected)
  expectPages(untouched, initial)
  assert resumeFlatHostMemory(current, first, gas, registers) == StepError.None
  runFlat(current, 1000)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  let second = observeFlatHostMemory(current)
  expectPages(first, expected)
  expected[0].bytes[0] = 17
  expectPages(second, expected)
  # Reset before accepting the second response must restore the first committed checkpoint.
  resetFlatFrame(current, input)
  expected[0].bytes[0] = 91
  expectPages(flatMemorySnapshot(current), expected)
  var later = newSeq[PageImage](expected.len)
  for page in 0..<expected.len: later[page] = expected[page]
  later[0].bytes[0] = 17
  expectPages(second, later)
  runFlat(current, 1000)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  let reset = observeFlatHostMemory(current)
  let resetGas = current.info.gas
  let resetRegisters = current.info.registers
  assert resumeFlatHostMemory(current, reset, resetGas, resetRegisters) == StepError.None
  runFlat(current, 1000)
  assert current.reason == StepError.None and current.exit == StepExit.Host
  expectPages(observeFlatHostMemory(current), expected)

checkpointEpoch(false)
checkpointEpoch(true)
echo "PASS dirty checkpoint epochs / sparse-dense-reversed writes / repeated observations / reset isolation"
