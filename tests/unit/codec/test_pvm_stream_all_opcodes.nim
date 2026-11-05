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

let mapped = memory()
var registers = default(RegisterFile)
let patterns = [0'u64, high(uint64), 0x8000000000000000'u64, 0x80000000'u64,
  0x10000'u64, 0x10fff'u64, 0x11ffc'u64, 0xffff0000'u64, 63'u64, 32'u64, 1'u64,
      0x10001'u64, 0x12345678'u64]
for index in 0..<13: registers[index] = RegisterValue(patterns[index])
var opcodes = 0
for op in 0..255:
  # Each operand layout sees zeroed, saturated and mixed bit patterns; all code uses exact marked boundaries.
  if validOpcode(byte(op)):
    inc opcodes
    for pattern in [0'u8, 255'u8, 17'u8]:
      var part = @[byte(op)]
      for index in 0..<24: part.add(pattern)
      let program = owner([part, @[0'u8]])
      let prepared = cache(program)
      for paid in [false, true]:
        for gas in [0'u64, 1'u64, 512'u64]:
          # A paid source exercises instruction mutation independently of pipeline affordability.
          let source = captureMachine(program, mapped, MachineInfo(
              pc: CodeAddress(0),
            gas: MachineGas(gas), blockCharged: paid,
                registers: registers)).value
          echo "CASE,", op, ",", pattern, ",", paid, ",", gas
          compare(source, prepared, 16, 100000)
assert opcodes == 139


echo "PASS Interpreter all 139 opcodes / fresh+reused / full CPU-memory-source-exit state"
# Every prefix of a folded-noop and arithmetic sequence checks synthetic budget barriers and their restoration.
let prefix = owner([@[2'u8], @[2'u8], @[51'u8, 7'u8, 9'u8], @[2'u8], @[131'u8, 7'u8, 1'u8], @[50'u8, 0'u8]])
var prefixRegs = default(RegisterFile)
prefixRegs[0] = RegisterValue(0xffff0000'u64)
let prefixSource = captureMachine(prefix, mapped, MachineInfo(pc: CodeAddress(0), gas: MachineGas(
    1000), registers: prefixRegs, blockCharged: false)).value
let prefixPlan = cache(prefix)
for budget in 0'u64..8'u64: compare(prefixSource, prefixPlan, budget, 100000)
# A refused source prefix never corrupts the cached handler later reused with enough budget.
for budget in [1'u64, 6'u64, 2'u64, 7'u64, 3'u64, 8'u64]: compare(prefixSource, prefixPlan, budget, 100000)
echo "PASS folded source budgets / exact terminal budget / temporary barrier restoration"

proc immediate(bytes: var seq[byte], value: uint64) =
  ## Fixed four-byte bit patterns are independent of the production operand decoder.
  for index in 0..<4: bytes.add(byte((value shr (8*index)) and 255))

for op in [30'u8, 31, 32, 33, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 70,
    71, 72, 73, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130]:
  # Every memory opcode selects its own prepared width/sign/address/source combination.
  for address in [0x10000'u64, 0x10fff'u64, 0x11ffc'u64, 0xffff0000'u64,
      0xffffffff'u64]:
    for alias in [false, true]:
      var part = @[op]
      if op <= 33:
        part.add(4)
        immediate(part, address)
        immediate(part, 0x89abcdef'u64)
      elif op >= 70 and op <= 73:
        part.add(79)
        immediate(part, 0)
        immediate(part, 0x89abcdef'u64)
      else:
        part.add(if op < 120: 15'u8 elif alias: 255'u8 else: 31'u8)
        immediate(part, if op < 120: address else: 0'u64)
      let program = owner([part, @[0'u8]])
      let prepared = cache(program)
      var selected = registers
      selected[1] = RegisterValue(address)
      if op >= 70 and op <= 73 or (op >= 120 and alias): selected[
          12] = RegisterValue(address)
      for access in [PageAccess.Inaccessible, PageAccess.ReadOnly,
          PageAccess.ReadWrite]:
        # Replacing the memory owner never changes prepared program facts or reuses old page permissions.
        var images = [pageImage(mapped, PageIndex(16)).value, pageImage(mapped,
            PageIndex(17)).value]
        images[1].access = access
        let memory = captureMemory(images, PageLimit(2)).value
        let source = captureMachine(program, memory, MachineInfo(
            gas: MachineGas(1000), registers: selected)).value
        compare(source, prepared, 2, 100000)

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


proc targetWorkingProgram(count: int, aliasedLoad: bool): Program =
  ## Three complete rounds visit every dynamic destination; final probes collide with valid ordinal tags after the cache is warm.
  var parts: seq[seq[byte]] = @[]
  var jumps: seq[uint32] = @[]
  let transferBytes = if aliasedLoad: 11 else: 6
  let blockBytes = 9+transferBytes
  for index in 0..<count:
    # Register7 counts actual visits; register9 independently accumulates destination identities.
    jumps.add(uint32(index*blockBytes))
    parts.add(@[149'u8, 0x77, 1])
    var checksum = @[149'u8, 0x99]
    immediate(checksum, uint64(index+1))
    parts.add(checksum)
    let ordinalAddress = if index+1 == count: 2'u64 else: uint64((index+2)*2)
    var transfer: seq[byte] = @[]
    if aliasedLoad:
      # The old base must be read before replacing that same register; offsets deliberately include negative signed-four-byte values.
      transfer = @[180'u8, 0x66, 4]
      immediate(transfer, uint64((index+1)*2))
      let priorBase = if index == 0: uint64(count*2) else: uint64(index*2)
      immediate(transfer, (ordinalAddress+0x100000000'u64-priorBase) and 0xffffffff'u64)
    else:
      # A zero base plus the literal two-byte-aligned selector visits the next original table entry.
      transfer = @[50'u8, 6]
      immediate(transfer, ordinalAddress)
    if index+1 == count:
      # Equality exits only after exactly three rounds; both branch destinations are genuine basic-block starts.
      var finish = @[170'u8, 0x87]
      immediate(finish, uint64(6+transferBytes))
      parts.add(finish)
    parts.add(transfer)
  parts.add(@[50'u8, 0]) # Register0 chooses halt, malformed address, invalid target or colliding out-of-table ordinal after warmup.
  parts.add(@[0'u8])
  jumps.add(3'u32) # Marked second arithmetic instruction is inside a block, never a legal dynamic target.
  jumps.add(1'u32) # Operand byte is unmarked.
  jumps.add(uint32(count*blockBytes+100)) # Beyond the complete code extent.
  owner(parts, jumps)

proc targetWorkingSource(program: Program, count: int, aliasedLoad: bool,
    selector: uint64): Machine =
  ## Source-owned registers choose the probe independently of cache contents and retain a predictable final counter/checksum.
  var initial = default(RegisterFile)
  initial[0] = RegisterValue(selector)
  initial[6] = RegisterValue(if aliasedLoad: uint64(count*2) else: 0'u64)
  initial[8] = RegisterValue(uint64(count*3))
  captureMachine(program, mapped, MachineInfo(gas: MachineGas(1000000), registers: initial)).value


for count in [5, 17, 65, 257, 513]:
  for alias in [false, true]:
    let program = targetWorkingProgram(count, alias)
    let plan = cache(program)
    for selector in [0xffff0000'u64, 0'u64, 1'u64, uint64((count+1)*2), uint64((count+2)*2), uint64(
        (count+3)*2), uint64((count+514)*2)]:
      let source = targetWorkingSource(program, count, alias, selector)
      compare(source, plan, 100000, 100000)
    let source = targetWorkingSource(program, count, alias, 0xffff0000'u64)
    for budget in [0'u64, 1, 2, 3, 4, 40, 80]: compare(source, plan, budget, 100000)
echo "PASS dynamic target working sets / aliases / full ordinals / invalid targets"

for balance in [0x8000000000000000'u64, high(uint64)]:
  let source = captureMachine(prefix, mapped, MachineInfo(pc: CodeAddress(0), gas: MachineGas(
      balance), registers: prefixRegs, blockCharged: false)).value
  for budget in 0'u64..8'u64: compare(source, prefixPlan, budget, 100000)
let refused = newFlatPlan(prefix, GasCycleLimit(1))
compare(prefixSource, refused, 8, 1)
echo "PASS unsigned high gas / pricing-policy refusal"

proc life(source: Machine, plan: FlatPlan) =
  ## Every mutable stream, partial budget overlay and private buffer retires after the cycle.
  compare(source, plan, 1, 100000)
  compare(source, plan, 8, 100000)
life(prefixSource, prefixPlan)
let before = getOccupiedMem()
for cycle in 0..<1000: life(prefixSource, prefixPlan)
let after = getOccupiedMem()
assert before == after
echo "PASS Interpreter ARC1000 unchanged"

# Each selected pair crosses every source-budget boundary and reenters its second node; alias/saturation patterns remain decoder-owned.
var fusedCases = 0
for codes in [[151'u8, 152'u8], [200'u8, 139'u8], [149'u8, 149'u8]]:
  for firstPattern in [0'u8, 17'u8, 255'u8]:
    for secondPattern in [0'u8, 17'u8, 255'u8]:
      var one = @[codes[0]]
      var two = @[codes[1]]
      for i in 0..<24:
        one.add(firstPattern)
        two.add(secondPattern)
      for gap in [false, true]:
        let parts = if gap: @[one, @[2'u8], two, @[50'u8, 0'u8]] else: @[one, two, @[50'u8, 0'u8]]
        let source = owner(parts)
        let plan = cache(source)
        for pc in [0'u64, if gap: 26'u64 else: 25'u64]:
          for paid in [false, true]:
            for gas in [0'u64, 1'u64, 1000'u64, high(uint64)]:
              let input = captureMachine(source, mapped, MachineInfo(pc: CodeAddress(pc),
                  gas: MachineGas(gas), blockCharged: paid, registers: registers)).value
              for budget in [0'u64, 1'u64, 2'u64, 3'u64, 8'u64, high(uint64)]:
                compare(input, plan, budget, 100000)
                inc fusedCases
echo "PASS fused-register boundaries /", fusedCases, "/ aliases / saturated decoding / independent second entry / paid-unpaid / folded gaps / uint64 gas-budget"

proc branchWord(bytes: var seq[byte], value: uint32) =
  ## Literal four-byte branch operands do not use the runtime operand decoder.
  for shift in 0..<4:
    bytes.add(byte((uint64(value) shr (8*shift)) and 255))

proc addBranchOwner(slots, branch, increment: byte, threshold: uint32, gap: bool,
    validTarget: bool = true): Program =
  ## Two genuine targets leave distinct literal markers; an optional folded noop forbids adjacency.
  var condition = @[83'u8, byte(0x40'u8 or branch)]
  branchWord(condition, threshold)
  branchWord(condition, if validTarget: 14'u32 else: 13'u32)
  var parts = @[@[131'u8, slots, increment]]
  if gap:
    # Noops retain their original source budget even though no physical worker is emitted.
    parts.add(@[2'u8])
  parts.add(condition)
  parts.add(@[51'u8, 6, 17])
  parts.add(@[0'u8])
  parts.add(@[51'u8, 6, 29])
  parts.add(@[0'u8])
  owner(parts)

proc branchCpu(left, right: MachineInfo, context: string) =
  ## Preserve every existing CPU equality, reporting the precise field only on a failure.
  assert uint64(left.pc) == uint64(right.pc), context & " pc actual=" & $uint64(left.pc) &
    " expected=" & $uint64(right.pc)
  assert uint64(left.gas) == uint64(right.gas), context & " gas actual=" & $uint64(left.gas) &
    " expected=" & $uint64(right.gas)
  assert uint64(left.gasDeficit) == uint64(right.gasDeficit), context & " deficit actual=" &
    $uint64(left.gasDeficit) & " expected=" & $uint64(right.gasDeficit)
  assert left.blockCharged == right.blockCharged, context & " paid actual=" & $left.blockCharged &
    " expected=" & $right.blockCharged
  for index in 0..<13:
    # Registers retain the original exact comparison, including unrelated and saturated lanes.
    assert uint64(left.registers[index]) == uint64(right.registers[index]), context & " register=" &
      $index & " actual=" & $uint64(left.registers[index]) & " expected=" & $uint64(right.registers[index])

proc branchPrefix(frame: var FlatFrame, program: Program, info: MachineInfo, budget: uint64,
    pages: openArray[PageImage], stage: string) =
  ## Single-instruction execution independently checks composition, charge/refund and original PCs.
  var context = stage & " entry=" & $uint64(info.pc) & " gas=" & $uint64(info.gas) &
    " paid=" & $info.blockCharged & " budget=" & $budget & " input-registers="
  for index in 0..<13:
    # Failure context identifies the complete immutable invocation input, without success output.
    context.add(" " & $index & ":" & $uint64(info.registers[index]))
  let captured = captureMemory(pages, PageLimit(2)).value
  let input = captureMachine(program, captured, info).value
  var expected = input
  var exit = StepExit.Continued
  var reason = StepError.StepLimitExceeded
  var consumed = 0'u64
  for attempt in 0'u64..<budget:
    # stepOnce uses the scalar adapter, never the newly selected two-source fused worker.
    let next = stepOnce(expected, GasCycleLimit(100000))
    assert next.error == StepError.None, context & " oracle attempt=" & $attempt &
      " error=" & $ord(next.error)
    expected = next.value.machine
    exit = next.value.exit
    if exit != StepExit.OutOfGas: inc consumed
    if exit != StepExit.Continued:
      reason = StepError.None
      break
  resetFlatFrame(frame, info)
  runFlat(frame, budget)
  assert frame.reason == reason and frame.exit == exit, context & " reason actual=" &
    $ord(frame.reason) & " expected=" & $ord(reason) & " exit actual=" & $ord(frame.exit) &
    " expected=" & $ord(exit)
  assert frame.remaining == budget-consumed, context & " remaining actual=" & $frame.remaining &
    " expected=" & $(budget-consumed) & " oracle-consumed=" & $consumed
  var wanted = machineInfo(expected).value
  if exit in [StepExit.Halt, StepExit.Panic]:
    # Recursive terminal execution normalizes PC; scalar stepping retains its terminal successor.
    wanted.pc = CodeAddress(0)
  branchCpu(frame.info, wanted, context & " final CPU")
  branchCpu(machineInfo(input).value, info, context & " immutable input CPU")
  checkFlatSource(frame, pages)
  let actual = flatMemorySnapshot(frame)
  for page in pages:
    # These pure operations cannot alter either original page bytes or permissions.
    let finalPage = pageImage(actual, page.index).value
    let sourcePage = pageImage(captured, page.index).value
    assert finalPage.access == page.access and sourcePage.access == page.access, context &
      " page access changed index=" & $uint32(page.index)
    assert finalPage.bytes == page.bytes and sourcePage.bytes == page.bytes, context &
      " page bytes changed index=" & $uint32(page.index)

proc branchCase(slots, condition, increment: byte, threshold: uint32, values: RegisterFile,
    destination: int, expectedValue: uint64, taken: bool): uint64 =
  ## Reuse one captured code owner across all changing source entries, budgets, paid state and gas.
  result = 0
  let pages = [pageImage(mapped, PageIndex(16)).value, pageImage(mapped, PageIndex(17)).value]
  for gap in [false, true]:
    # A genuinely adjacent branch may fuse; its folded-gap control must retain scalar composition.
    let context = "slots=" & $uint64(slots) & " condition=" & $uint64(condition) &
      " increment=" & $uint64(increment) & " threshold=" & $uint64(threshold) & " gap=" & $gap &
      " destination=" & $destination & " before=" & $uint64(values[destination]) &
      " literal-after=" & $expectedValue & " taken=" & $taken
    let program = addBranchOwner(slots, condition, increment, threshold, gap)
    var captured = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert captured.error == FlatError.None, context & " prepare error=" & $ord(captured.error)
    let plan = takeValue(captured)
    let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000),
      blockCharged: false, registers: values)
    var frame = newFlatFrame(plan, pages, initial)
    when defined(pvmStreamFusionReceipt):
      assert not flatAddBranchFusionActive(frame, 0), context & " activation before run expected=false"
    branchPrefix(frame, program, initial, 0, pages, context & " zero")
    when defined(pvmStreamFusionReceipt):
      assert not flatAddBranchFusionActive(frame, 0), context & " activation after zero expected=false"
    branchPrefix(frame, program, initial, 1, pages, context & " one")
    when defined(pvmStreamFusionReceipt):
      # A temporary branch-budget barrier cannot certify either cached arm or enable fusion.
      assert not flatAddBranchFusionActive(frame, 0), context & " activation after one expected=false"
    branchPrefix(frame, program, initial, 8, pages, context & " full")
    assert uint64(frame.info.registers[destination]) == expectedValue, context &
      " literal result actual=" & $uint64(frame.info.registers[destination]) & " expected=" & $expectedValue
    assert uint64(frame.info.registers[6]) == (if taken: 29'u64 else: 17'u64), context &
      " literal marker actual=" & $uint64(frame.info.registers[6]) & " expected=" &
      $(if taken: 29'u64 else: 17'u64)
    when defined(pvmStreamFusionReceipt):
      assert flatAddBranchFusionActive(frame, 0) == (not gap), context &
          " warm activation actual=" &
        $flatAddBranchFusionActive(frame, 0) & " expected=" & $(not gap)
    let priced = blockGas(program, CodeAddress(0), GasCycleLimit(100000))
    assert priced.error == GasError.None, context & " block price error=" & $ord(priced.error)
    let price = uint64(priced.value)
    assert price > 0 and price < 1000000, context & " unexpected block price=" & $price
    for pc in [0'u64, if gap: 4'u64 else: 3'u64]:
      # The branch itself remains a separately addressable paid or unpaid original instruction.
      for paid in [false, true]:
        for gas in [0'u64, 1, price-1, price, price+1, high(uint64)]:
          var input = initial
          input.pc = CodeAddress(pc)
          input.blockCharged = paid
          input.gas = MachineGas(gas)
          for budget in [0'u64, 1, 2, 3, 4, 5, 8, high(uint64)]:
            branchPrefix(frame, program, input, budget, pages, context & " matrix")
            inc result
    var stream = takeFlatStream(frame)
    when defined(pvmStreamFusionReceipt):
      assert not flatAddBranchFusionActive(frame, 0), context & " moved-from activation expected=false"
    var retained = newFlatFrame(plan, pages, initial)
    restoreFlatStream(retained, stream)
    branchPrefix(retained, program, initial, 8, pages, context & " restored stream")
    when defined(pvmStreamFusionReceipt):
      assert flatAddBranchFusionActive(retained, 0) == (not gap), context &
          " restored activation actual=" &
        $flatAddBranchFusionActive(retained, 0) & " expected=" & $(not gap)
    var held = takeFlatStream(retained)
    let heldNodes = streamNodes(held)
    let changed = addBranchOwner(slots, condition, increment, threshold xor 1'u32, gap)
    var different = prepareFlatPlan(changed, GasCycleLimit(100000), defaultFlatLimits(), false)
    assert different.error == FlatError.None, context & " changed plan error=" & $ord(
        different.error)
    let changedPlan = takeValue(different)
    var rejected = newFlatFrame(changedPlan, pages, initial)
    restoreFlatStream(rejected, held)
    runFlat(rejected, 8)
    assert rejected.reason == StepError.InvalidPreparedProgram and streamNodes(held) == heldNodes,
      context & " changed-source rejection reason=" & $ord(rejected.reason) &
          " held nodes actual=" &
      $streamNodes(held) & " expected=" & $heldNodes
    when defined(pvmStreamFusionReceipt):
      assert not flatAddBranchFusionActive(rejected, 0), context & " rejected activation expected=false"
    restoreFlatStream(retained, held)
    branchPrefix(retained, program, initial, 8, pages, context & " restored after rejection")

type BranchLiteral = object ## Independent width/wrap equations, without another opcode evaluator.
  before: uint64
  increment: byte
  threshold: uint32
  after: uint64
  taken: bool

const branchLiterals = [
  BranchLiteral(before: 0, increment: 1, threshold: 2, after: 1, taken: true),
  BranchLiteral(before: 1, increment: 1, threshold: 2, after: 2, taken: false),
  BranchLiteral(before: 0x7fffffff, increment: 1, threshold: 0,
    after: 0xffffffff80000000'u64, taken: false),
  BranchLiteral(before: 0xffffffff'u64, increment: 1, threshold: 1, after: 0, taken: true),
  BranchLiteral(before: 0x12345678ffffffff'u64, increment: 1, threshold: 1, after: 0, taken: true),
  BranchLiteral(before: 0, increment: 255, threshold: 0xffffffff'u32,
    after: high(uint64), taken: false),
  BranchLiteral(before: 0x80000000'u64, increment: 0, threshold: 0x7fffffff,
    after: 0xffffffff80000000'u64, taken: false),
  BranchLiteral(before: 0x7fffffff, increment: 1, threshold: 0xffffffff'u32,
    after: 0xffffffff80000000'u64, taken: true)]

var branchControls = 0'u64
for alias in 0..<3:
  # Explicit source encodings cover two real lanes and saturated register IDs without a test decoder.
  let lane = if alias == 0: 7 elif alias == 1: 8 else: 12
  let slots = [0x77'u8, 0x88, 0xff][alias]
  let condition = if alias == 2: 15'u8 else: byte(lane)
  for literal in branchLiterals:
    var values = registers
    values[lane] = RegisterValue(literal.before)
    branchControls += branchCase(slots, condition, literal.increment, literal.threshold, values,
      lane, literal.after, literal.taken)
for condition in [7'u8, 8]:
  # The branch must use its actual lane after the write, whether aliased with the source or destination.
  var values = registers
  values[7] = RegisterValue(5)
  values[8] = RegisterValue(13)
  branchControls += branchCase(0x78, condition, 1, 6, values, 8, 6, condition == 7)
assert branchControls == 9984, "add32-branch matrix count actual=" & $branchControls & " expected=9984"
echo "PASS add32-branch Step prefixes / literals / aliases / width / paid-interior / retained-owner"

block retainedBranchState:
  # One service-like code lifetime observes both branch outcomes as the caller changes block state.
  let program = addBranchOwner(0x77, 7, 1, 2, false)
  var captured = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
  assert captured.error == FlatError.None, "retained-state prepare error=" & $ord(captured.error)
  let plan = takeValue(captured)
  let pages = [pageImage(mapped, PageIndex(16)).value, pageImage(mapped, PageIndex(17)).value]
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000),
    registers: registers, blockCharged: false)
  var frame = newFlatFrame(plan, pages, info)
  for before in [0'u64, 1, 0, 1]:
    # Retain the warmed code/targets while replacing invocation-local register state.
    info.registers[7] = RegisterValue(before)
    let context = "retained-state slots=119 condition=7 increment=1 threshold=2 gap=false before=" & $before
    branchPrefix(frame, program, info, 8, pages, context)
    assert uint64(frame.info.registers[7]) == before+1, context & " result actual=" &
      $uint64(frame.info.registers[7]) & " expected=" & $(before+1)
    assert uint64(frame.info.registers[6]) == (if before == 0: 29'u64 else: 17'u64), context &
      " marker actual=" & $uint64(frame.info.registers[6]) & " expected=" &
      $(if before == 0: 29'u64 else: 17'u64)
    when defined(pvmStreamFusionReceipt):
      assert flatAddBranchFusionActive(frame, 0), context & " retained activation expected=true"

block rejectedBranchTarget:
  # An invalid taken target never becomes a positive cached capability, even on a fallthrough run.
  let program = addBranchOwner(0x77, 7, 1, 2, false, false)
  var captured = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
  assert captured.error == FlatError.None, "invalid-target prepare error=" & $ord(captured.error)
  let plan = takeValue(captured)
  let pages = [pageImage(mapped, PageIndex(16)).value, pageImage(mapped, PageIndex(17)).value]
  var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000000),
    registers: registers, blockCharged: false)
  var frame = newFlatFrame(plan, pages, info)
  for before in [0'u64, 1]:
    info.registers[7] = RegisterValue(before)
    let context = "invalid-target slots=119 condition=7 increment=1 threshold=2 gap=false before=" & $before
    branchPrefix(frame, program, info, 8, pages, context)
    when defined(pvmStreamFusionReceipt):
      assert not flatAddBranchFusionActive(frame, 0), context & " invalid-target activation expected=false"

when defined(pvmStreamFusionReceipt):
  echo "PASS add32-branch activation / positive arms / partial refusal / changing state"
