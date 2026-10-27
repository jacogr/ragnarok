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

proc compare(input: Machine, prepared: FlatPlan, steps, cycles: uint64, warm: bool = false) =
  ## A fresh and reused handler stream see the same original registers and private input reset on each call.
  let info = machineInfo(input).value
  let mem = memoryOf(input).value
  let pages = [pageImage(mem, PageIndex(16)).value, pageImage(mem, PageIndex(17)).value]
  let expected = execute(input, ExecutionStepLimit(steps), GasCycleLimit(cycles))
  var expectedPrefix = input
  if expected.error == StepError.StepLimitExceeded:
    # A local quota failure has no success payload: independently step the entire prefix to check its hidden CPU boundary.
    for attempted in 0'u64..<steps:
      let next = stepOnce(expectedPrefix, GasCycleLimit(cycles))
      assert next.error == StepError.None and next.value.exit == StepExit.Continued
      expectedPrefix = next.value.machine
  var frame = newFlatFrame(prepared, pages, info)
  if warm:
    # Warm with sufficient gas and a bounded independent invocation, then restore the actual caller state below.
    var warmInfo = info
    warmInfo.gas = MachineGas(high(uint64))
    warmInfo.blockCharged = false
    resetFlatFrame(frame, warmInfo)
    runFlat(frame, 64)
    checkFlatSource(frame)
  for repeat in 0..<2:
    resetFlatFrame(frame, info)
    runFlat(frame, steps)
    same(frame, expected)
    if expected.error == StepError.StepLimitExceeded:
      # Budget boundaries retain exact PC, registers, gas and paid state even after combined-handler warmup.
      sameCpu(frame.info, machineInfo(expectedPrefix).value)
      assert frame.remaining == 0
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


let mapped = memory()
var registers = default(RegisterFile)
registers[0] = RegisterValue(0xffff0000'u64)
registers[1] = RegisterValue(0x123456789abcdef0'u64)
let firstOperations = @[@[0'u8], @[2'u8], @[10'u8, 1'u8], @[51'u8, 7'u8, 9'u8],
  firstMemoryPart(62, 65537), firstMemoryPart(58, 69631), firstMemoryPart(62, 73727),
  @[50'u8, 0'u8], @[40'u8, 0'u8], @[40'u8, 255'u8]]
var cases = 0
for noops in [0, 1, 2, 7]:
  for first in firstOperations:
    var parts: seq[seq[byte]] = @[]
    for i in 0..<noops: parts.add(@[2'u8])
    parts.add(first)
    parts.add(@[51'u8, 7'u8, 9'u8])
    parts.add(@[50'u8, 0'u8])
    parts.add(@[0'u8])
    let program = owner(parts)
    for cycles in [1'u64, 100000'u64]:
      let plan = newFlatPlan(program, GasCycleLimit(cycles))
      for paid in [false, true]:
        for gas in [0'u64, 1'u64, 2'u64, 1000'u64, 0x8000000000000000'u64, high(uint64)]:
          let source = captureMachine(program, mapped, MachineInfo(pc: CodeAddress(0),
            gas: MachineGas(gas), blockCharged: paid, registers: registers)).value
          for budget in 0'u64..10'u64:
            # Every run uses a genuine source owner; reuse also verifies restoration of the temporary first-handler barrier.
            compare(source, plan, budget, cycles)
            inc cases
assert cases == 10560
echo "PASS direct entry /", cases, "/ full and partial reservations / leading noops / first host-fault-panic-halt / unsigned gas / paid suffix / failed prices / restored barriers"


var branchCases = 0
for mode in [0, 1, 2]:
  # Forward, backward-loop and invalid-arm programs keep both taken and untaken branch behavior observable.
  for descriptor in [0x11'u8, 0x21'u8, 0xff'u8]:
    let destination = min(12, int(descriptor mod 16))
    var branch = @[88'u8, byte(16+destination), 3'u8]
    immediate(branch, if mode == 0: 12'u64 elif mode == 1: 0xfffffffd'u64 else: 1'u64)
    let source = owner([@[131'u8, descriptor, 1'u8], branch,
      @[51'u8, 7'u8, 17'u8], @[50'u8, 0'u8], @[51'u8, 7'u8, 34'u8], @[50'u8, 0'u8]])
    let plan = cache(source)
    for bits in [0'u64, 0x7fffffff'u64, 0x80000000'u64, 0xffffffff'u64,
        0x8000000000000000'u64, high(uint64)]:
      var selected = registers
      selected[1] = RegisterValue(bits)
      selected[2] = RegisterValue(bits xor 0xffffffff'u64)
      selected[12] = RegisterValue(bits)
      for paid in [false, true]:
        # Whole-block gas refusal must precede arithmetic; prepaid reentry still respects every source quota.
        for gas in [0'u64, 1'u64, 2'u64, 1000'u64, high(uint64)]:
          let input = captureMachine(source, mapped, MachineInfo(pc: CodeAddress(0),
            gas: MachineGas(gas), blockCharged: paid, registers: selected)).value
          for budget in [0'u64, 1'u64, 2'u64, 3'u64, 4'u64, 7'u64, 10'u64, 16'u64]:
            # Fresh/reused pairs exercise cold arm validation, cached branches, signed32 wrap, aliases and quota restoration.
            compare(input, plan, budget, 100000)
            compare(input, plan, budget, 100000, true)
            inc branchCases
assert branchCases == 4320
echo "PASS register-branch /4320cases / alias-saturation-signed-wrap / both arms-invalid targets / cold+cached / exact quota CPU"


var shapeCases = 0
for family in [0, 1]:
  for mode in [0, 1, 2]:
    # These two independently encoded three-op blocks cover immediate and register terminal comparisons.
    let first = if family == 0: @[200'u8, 0x21, 3] else: @[151'u8, 0x11, 1]
    let second = if family == 0: @[139'u8, 0x33, 1] else: @[152'u8, 0x11, 1]
    var branch = if family == 0: @[82'u8, 0x13, 3] else: @[173'u8, 0x21]
    immediate(branch, if mode == 0: (if family == 0: 12'u64 else: 11'u64)
      elif mode == 1: 0xfffffffa'u64 else: 1'u64)
    let source = owner([first, second, branch, @[51'u8, 7, 17], @[50'u8, 0], @[51'u8, 7, 34], @[
        50'u8, 0]])
    let plan = cache(source)
    for bits in [0'u64, 0x7fffffff'u64, 0x80000000'u64, 0xffffffff'u64,
        0x8000000000000000'u64, high(uint64)]:
      var selected = registers
      selected[1] = RegisterValue(bits)
      selected[2] = RegisterValue(bits xor 0x55555555'u64)
      for paid in [false, true]:
        for gas in [0'u64, 1'u64, 2'u64, 3'u64, 1000'u64, high(uint64)]:
          let input = captureMachine(source, mapped, MachineInfo(pc: CodeAddress(0),
            gas: MachineGas(gas), blockCharged: paid, registers: selected)).value
          for budget in 0'u64..8'u64:
            # Warm before short quotas as well as after full runs: partial fallback must precede every skipped operation.
            compare(input, plan, budget, 100000)
            compare(input, plan, budget, 100000, true)
            inc shapeCases
assert shapeCases == 3888
echo "PASS charged shapes /3888cases / cold+warm partial fallback / both comparison forms / gas and prefix CPU"


proc compareCycle(source: Program, mapped: Memory, registers: RegisterFile): int =
  ## Every concrete cycle graph sees the same gas/quota cross-check, including a warm stream before short prefixes.
  result = 0
  let plan = cache(source)
  for bits in [0'u64, 1'u64, 0x7fffffff'u64, 0x80000000'u64, 0xffffffff'u64, high(uint64)]:
    var selected = registers
    selected[1] = RegisterValue(bits)
    selected[2] = RegisterValue(bits xor 0x55555555'u64)
    for paid in [false, true]:
      for gas in [0'u64, 1'u64, 2'u64, 3'u64, 7'u64, 8'u64, 9'u64, 1000'u64, high(uint64)]:
        let input = captureMachine(source, mapped, MachineInfo(pc: CodeAddress(0),
          gas: MachineGas(gas), blockCharged: paid, registers: selected)).value
        for budget in [0'u64, 1'u64, 2'u64, 3'u64, 4'u64, 5'u64, 6'u64, 7'u64,
            8'u64, 9'u64, 15'u64, 16'u64, 17'u64, 23'u64, 24'u64, 25'u64]:
          # Cold and fully warmed streams must match independent stepping at every block/cycle edge and exhausted allowance.
          compare(input, plan, budget, 100000)
          compare(input, plan, budget, 100000, true)
          inc result

var cycleCases = 0
for order in @[@[0, 2, 1], @[1, 0, 2], @[2, 1, 0], @[0, 1, 2], @[0, 2], @[0, 2, 1, 0, 2, 1]]:
  # Rotated cycles, wrong-order exits and two-block prefixes exercise every positive and refused handoff.
  var parts: seq[seq[byte]] = @[]
  var position = 0
  for at in 0..<order.len:
    let kind = order[at]
    if kind == 0: parts.add(@[131'u8, 0x11, byte(if at >= 3: 2 else: 1)])
    elif kind == 1:
      parts.add(@[200'u8, 0x21, 3])
      parts.add(@[139'u8, 0x33, byte(if at >= 3: 2 else: 1)])
    else:
      parts.add(@[151'u8, 0x11, 1])
      parts.add(@[152'u8, 0x11, 1])
    let prefix = if kind == 0: 3 else: 6
    let branchBytes = if kind == 2: 6 else: 7
    var branch = if kind == 0: @[88'u8, 0x11, 3] elif kind == 1: @[82'u8, 0x13, 3] else: @[173'u8, 0x21]
    # Intermediate arms coincide at the actual next block; the final taken arm returns to the genuine entry boundary.
    let displacement = if at+1 < order.len: uint64(branchBytes)
      else: (0x100000000'u64-uint64(position+prefix)) and 0xffffffff'u64
    immediate(branch, displacement)
    parts.add(branch)
    position+=prefix+branchBytes
  parts.add(@[50'u8, 0])
  cycleCases+=compareCycle(owner(parts), mapped, registers)

# A branch may choose another record of the same shape after a closed round; stable coordinates must exit before that record is skipped.
var diamondA = @[88'u8, 0x11, 3]
immediate(diamondA, 34)
var diamondFalse = @[173'u8, 0x21]
immediate(diamondFalse, 6)
var diamondB = @[82'u8, 0x13, 3]
immediate(diamondB, 0xffffffe4'u64)
var diamondTrue = @[173'u8, 0x21]
immediate(diamondTrue, 0xffffffeb'u64)
let diamond = owner([@[131'u8, 0x11, 1], diamondA, @[151'u8, 0x11, 1], @[152'u8, 0x11, 1],
  diamondFalse, @[200'u8, 0x21, 3], @[139'u8, 0x33, 1], diamondB, @[50'u8, 0],
  @[151'u8, 0x11, 2], @[152'u8, 0x11, 1], diamondTrue, @[50'u8, 0]])
cycleCases+=compareCycle(diamond, mapped, registers)
assert cycleCases == 12096
echo "PASS charged cycles /12096cases / concrete rotations-wrong edges-two-block exits / different records-same shape / every gas and quota boundary"


var predicateCases = 0
let branchBits = [0'u64, 1'u64, 0x7fffffff'u64, 0x80000000'u64, 0xffffffff'u64,
  0x100000000'u64, 0x7fffffffffffffff'u64, 0x8000000000000000'u64, high(uint64)]
for opcode in [81'u8, 82, 83, 84, 85, 86, 87, 88, 89, 90, 170, 171, 172, 173, 174, 175]:
  # Every conditional opcode has genuine distinct taken/fallthrough blocks; immediate forms retain their four-byte sign extension.
  for right in branchBits:
    var branch = if opcode <= 90: @[opcode, 0x41'u8] else: @[opcode, 0x21'u8]
    if opcode <= 90: immediate(branch, right)
    immediate(branch, if opcode <= 90: 15'u64 else: 11'u64)
    let source = owner([branch, @[51'u8, 7, 17], @[50'u8, 0], @[51'u8, 7, 34], @[50'u8, 0]])
    let plan = cache(source)
    for left in branchBits:
      var selected = registers
      selected[1] = RegisterValue(left)
      selected[2] = RegisterValue(right)
      for paid in [false, true]:
        for gas in [0'u64, 1'u64, 1000'u64, high(uint64)]:
          let input = captureMachine(source, mapped, MachineInfo(pc: CodeAddress(0),
            gas: MachineGas(gas), blockCharged: paid, registers: selected)).value
          for budget in 0'u64..4'u64:
            # The independent interpreter selects each arm and exposes its exact prefix/gas/paid state before and after cache warmup.
            compare(input, plan, budget, 100000)
            inc predicateCases
assert predicateCases == 51840
echo "PASS all16conditional comparisons /51840boundary cases / signed-unsigned-immediate-register / full CPU and source quotas"


var suffixCases = 0
for family in [0, 1, 2]:
  for noops in [1, 7]:
    # An uncharged interior entry still pays its containing block's price, while its source allowance counts only the entered suffix.
    var parts: seq[seq[byte]] = @[]
    for i in 0..<noops: parts.add(@[2'u8])
    if family == 0: parts.add(@[131'u8, 0x11, 1])
    elif family == 1:
      parts.add(@[200'u8, 0x21, 3])
      parts.add(@[139'u8, 0x33, 1])
    else:
      parts.add(@[151'u8, 0x11, 1])
      parts.add(@[152'u8, 0x11, 1])
    var branch = if family == 0: @[88'u8, 0x11, 3]
      elif family == 1: @[82'u8, 0x13, 3] else: @[173'u8, 0x21]
    immediate(branch, if family == 2: 11'u64 else: 12'u64)
    parts.add(branch)
    parts.add(@[51'u8, 7, 17])
    parts.add(@[50'u8, 0])
    parts.add(@[51'u8, 7, 34])
    parts.add(@[50'u8, 0])
    let source = owner(parts)
    let plan = cache(source)
    for bits in [0'u64, 1'u64, 0x7fffffff'u64, 0x80000000'u64, 0xffffffff'u64, high(uint64)]:
      var selected = registers
      selected[1] = RegisterValue(bits)
      selected[2] = RegisterValue(bits xor 0x55555555'u64)
      for paid in [false, true]:
        for gas in [0'u64, 1'u64, 2'u64, 3'u64, 4'u64, 10'u64, 1000'u64, high(uint64)]:
          let seeded = captureMachine(source, mapped, MachineInfo(pc: CodeAddress(uint64(noops)),
            gas: MachineGas(gas), blockCharged: paid, registers: selected))
          assert seeded.error == MachineError.None
          for budget in 0'u64..5'u64:
            # Both the cold and warmed prepared suffix must preserve full pricing and exact per-instruction prefixes.
            compare(seeded.value, plan, budget, 100000)
            compare(seeded.value, plan, budget, 100000, true)
            inc suffixCases
assert suffixCases == 3456
echo "PASS sealed source counts /3456interior suffix cases / containing-block gas distinct from entered source count"
