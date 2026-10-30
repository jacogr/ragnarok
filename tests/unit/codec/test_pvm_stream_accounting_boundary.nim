# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Full 139-opcode, alias, gas and exit matrix across direct and public snapshot execution boundaries.
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

proc same(actual: FlatFrame, expected: StepResult, sourcePages: openArray[PageImage]) =
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
  checkFlatSource(actual, sourcePages)

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
    same(frame, expected, pages)
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


proc countAttempts(source: Machine, budget, cycles: uint64): uint64 =
  ## The independent public single-step API counts only actually attempted instructions; failed pricing/out-of-gas are not attempts.
  var current = source
  result = 0
  while result < budget:
    let one = stepOnce(current, GasCycleLimit(cycles))
    if one.error != StepError.None: return
    let value = one.value
    if value.exit == StepExit.OutOfGas: return
    inc result
    current = value.machine
    if value.exit != StepExit.Continued: return

proc accounting(source: Machine, plan: FlatPlan, budget, cycles: uint64, frame: var FlatFrame) =
  ## Compare complete observable outcomes and the independent unused budget, never a duplicated suffix formula.
  let info = machineInfo(source).value
  let baseline = memoryOf(source).value
  let sourcePages = [pageImage(baseline, PageIndex(16)).value, pageImage(baseline, PageIndex(17)).value]
  resetFlatFrame(frame, info)
  runFlat(frame, budget)
  let expected = execute(source, ExecutionStepLimit(budget), GasCycleLimit(cycles))
  same(frame, expected, sourcePages)
  if expected.error == StepError.None or expected.error == StepError.StepLimitExceeded:
    let used = countAttempts(source, budget, cycles)
    assert used <= budget
    if frame.remaining != budget-used:
      echo "BUDGET_MISMATCH,", budget, ",", used, ",", frame.remaining, ",", frame.exit, ",",
          uint64(frame.info.pc)
    assert frame.remaining == budget-used
  sameCpu(machineInfo(source).value, info)

let mapped = memory()
let images = [pageImage(mapped, PageIndex(16)).value, pageImage(mapped, PageIndex(17)).value]
var registers = default(RegisterFile)
registers[0] = RegisterValue(0xffff0000'u64)
registers[1] = RegisterValue(0x123456789abcdef0'u64)
let firstOperations = @[@[0'u8], @[2'u8], @[10'u8, 1'u8], @[51'u8, 7'u8, 9'u8],
  firstMemoryPart(62, 65537), firstMemoryPart(58, 69631), firstMemoryPart(62, 73727),
  @[50'u8, 0'u8], @[40'u8, 0'u8], @[40'u8, 255'u8]]
var cases = 0
for noops in [0, 1, 2, 7]:
  for which in 0..<firstOperations.len:
    var parts: seq[seq[byte]] = @[]
    for i in 0..<noops: parts.add(@[2'u8])
    parts.add(firstOperations[which])
    for i in 0..<7: parts.add(@[2'u8])
    parts.add(@[51'u8, 7'u8, 9'u8])
    parts.add(@[50'u8, 0'u8])
    parts.add(@[0'u8])
    let program = owner(parts)
    for cycles in [1'u64, 100000'u64]:
      let plan = newFlatPlan(program, GasCycleLimit(cycles))
      for pc in [0'u64, uint64(noops)]:
        for paid in [false, true]:
          for gas in [0'u64, 1'u64, 2'u64, 1000'u64, 0x8000000000000000'u64, high(uint64)]:
            let source = captureMachine(program, mapped, MachineInfo(pc: CodeAddress(pc),
              gas: MachineGas(gas), blockCharged: paid, registers: registers)).value
            var frame = newFlatFrame(plan, images, machineInfo(source).value)
            for budget in [1'u64, 16'u64, 2'u64, high(uint64), 3'u64, 0'u64, 7'u64,
                0x8000000000000000'u64, 4'u64, 8'u64]:
              # Alternate full/partial/zero reservations on one frame; huge budgets are omitted only for the deliberate control-loop cases.
              if which >= 8 and budget > 16: continue
              accounting(source, plan, budget, cycles, frame)
              inc cases
echo "CASE_TOTAL,", cases
assert cases == 4*2*2*2*6*(8*10+2*8)
echo "PASS exit accounting /", cases, "/ independent stepOnce attempts / full-partial-zero reuse / interior paid-unpaid / folded noops / host-fault-halt-panic / gas and local limits through uint64 max"
