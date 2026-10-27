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
