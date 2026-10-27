# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Local JIT alias/overflow and reservation witness against the engine's bounded single-step adapter.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, gas, step, registers, gas_plan, gas_memo]
when defined(pvmArm64Jit):
  import ../../src/pvm/internal/arm64_jit
import ../../src/pvm/internal/handler_stream
proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Test framing uses the independent natural codec without borrowing program storage.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len:
    # Only the explicitly encoded prefix belongs to the output.
    bytes.add(encoded.bytes[index])

proc captureOwner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): ProgramResult[Program] =
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
  decoded

proc owner(parts: openArray[seq[byte]], jumps: openArray[uint32] = []): Program =
  ## Positive fixtures must retain genuine source admission; malformed fixtures inspect captureOwner directly.
  let decoded = captureOwner(parts, jumps)
  assert decoded.error == ProgramError.None
  decoded.value


when defined(pvmArm64Jit):
  var nativeCases = 0
  for opcode in 0..255:
    if not supportedArmOpcode(byte(opcode)): continue
    for pattern in [0'u8, 17, 128, 255]:
      var part = @[byte(opcode)]
      for position in 0..<24: part.add(pattern)
      let source = owner([part, part, part, part, @[0'u8]])
      let prepared = newFlatPlan(source, GasCycleLimit(100000))
      for seed in [0'u64, 31, 32, 63, 64, 127, 0x80000000'u64, 0xffffffff'u64,
          0x8000000000000000'u64, high(uint64)]:
        # The independent register evaluator has no code-generation path or resident-register analysis.
        var original = default(RegisterFile)
        for slot in 0..<13: original[slot] = RegisterValue(seed xor uint64(slot))
        let first = evaluateRegisters(source, CodeAddress(0), original)
        assert first.error == RegisterError.None
        let second = evaluateRegisters(source, CodeAddress(25), first.value)
        assert second.error == RegisterError.None
        let third = evaluateRegisters(source, CodeAddress(50), second.value)
        assert third.error == RegisterError.None
        let fourth = evaluateRegisters(source, CodeAddress(75), third.value)
        assert fourth.error == RegisterError.None
        let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: original)
        var frame = newFlatFrame(prepared, [], info)
        runFlat(frame, 100)
        assert frame.reason == StepError.None and frame.exit == StepExit.Panic
        for slot in 0..<13:
          if frame.info.registers[slot] != fourth.value[slot]:
            echo "NATIVE_MISMATCH,", opcode, ",", pattern, ",", seed, ",", slot
            assert false, "native register lowering differs from evaluator"
        let coverage = flatArmStatistics(frame)
        when defined(pvmArm64JitRefuse):
          assert coverage[2] == 0
        else:
          assert coverage[2] == 4
        inc nativeCases
  echo "ARM_REGISTER_CASES,", nativeCases

var nativeOperations = 0'u64
var cases = 0
for pattern in [0'u8, 17, 128, 255]:
  var parts: seq[seq[byte]] = @[]
  for index in 0..<72:
    # Mixed destinations include full aliases and saturated IDs; large padding admits exact decoder-selected immediates.
    let opcodes = [132'u8, 133, 134, 149, 200, 201]
    var part = @[opcodes[index mod 6]]
    for byteIndex in 0..<24: part.add(pattern)
    parts.add(part)
  parts.add(@[0'u8])
  let program = owner(parts)
  let plan = newFlatPlan(program, GasCycleLimit(100000))
  let empty = captureMemory([], PageLimit(2)).value
  for seed in [0'u64, high(uint64), 0x8000000000000000'u64, 0x123456789abcdef0'u64]:
    for paid in [false, true]:
      for gas in [0'u64, 1, 1000]:
        var registers = default(RegisterFile)
        for slot in 0..<13: registers[slot] = RegisterValue(seed xor uint64(slot))
        let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), registers: registers,
            blockCharged: paid)
        let source = captureMachine(program, empty, initial).value
        var frame = newFlatFrame(plan, [], initial)
        for budget in [0'u64, 1, 2, 7, 35, 36, 37, 38, 63, 64, 65, 71, 72, 73, 74, 100]:
          # Reuse compiled fragments around partial barriers and zero/low gas, without retaining mutable registers.
          var current = source
          var expectedExit = StepExit.Continued
          var reason = StepError.StepLimitExceeded
          for attempted in 0'u64..<budget:
            let next = stepOnce(current, GasCycleLimit(100000))
            assert next.error == StepError.None
            current = next.value.machine
            expectedExit = next.value.exit
            if expectedExit != StepExit.Continued:
              reason = StepError.None
              break
          resetFlatFrame(frame, initial)
          runFlat(frame, budget)
          let wanted = machineInfo(current).value
          assert frame.reason == reason and frame.exit == expectedExit, "reason/exit"
          # Ordinary execution normalizes halt/panic PC to zero; stepOnce deliberately retains its terminal source site.
          let wantedPc = if expectedExit in [StepExit.Halt, StepExit.Panic]: 0'u64 else: uint64(wanted.pc)
          assert uint64(frame.info.pc) == wantedPc, "PC"
          assert uint64(frame.info.gas) == uint64(wanted.gas), "gas"
          assert uint64(frame.info.gasDeficit) == uint64(wanted.gasDeficit), "deficit"
          assert frame.info.blockCharged == wanted.blockCharged, "charged"
          for slot in 0..<13: assert frame.info.registers[slot] == wanted.registers[slot], "register"
          checkFlatSource(frame)
          inc cases
        when defined(pvmArm64Jit):
          let observed = flatArmStatistics(frame)
          nativeOperations+=observed[2]
when defined(pvmArm64Jit):
  # A checked matrix that only falls back is not evidence that emitted instructions executed.
  when defined(pvmArm64JitRefuse):
    assert nativeOperations == 0
  else:
    assert nativeOperations > 0
  echo "ARM_WITNESS,", cases, ",", nativeOperations
else:
  echo "INTERPRETER_WITNESS,", cases

# Stream transfer drops native entries before changing emission history; the restored checked stream remains reusable.
let transferProgram = owner([@[200'u8, 0, 0], @[201'u8, 0, 0], @[200'u8, 0, 0], @[201'u8, 0, 0], @[0'u8]])
let transferPlan = newFlatPlan(transferProgram, GasCycleLimit(100000))
let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
var first = newFlatFrame(transferPlan, [], initial)
runFlat(first, 100)
when defined(pvmArm64Jit):
  let live = flatArmStatistics(first)
  when defined(pvmArm64JitRefuse):
    assert live[0] == 0 and live[1] == 0
  else:
    assert live[0] == 1 and live[1] == 1 and live[2] == 4
var stream = takeFlatStream(first)
var second = newFlatFrame(transferPlan, [], initial)
restoreFlatStream(second, stream)
runFlat(second, 100)
echo "TRANSFER,", second.exit, ",", second.reason
assert second.exit == StepExit.Panic and second.reason == StepError.None
checkFlatSource(second)
when defined(pvmArm64Jit):
  let transferred = flatArmStatistics(second)
  echo "TRANSFER_STATS,", transferred[0], ",", transferred[1]
  when defined(pvmArm64JitRefuse):
    assert transferred[0] == 0 and transferred[1] == 0
  else:
    assert transferred[0] == 1 and transferred[1] == 2
    assert transferred[2] == 8
  var retained = takeFlatStream(second)
  let retainedNodes = streamNodes(retained)
  var foreign = newFlatFrame(newFlatPlan(transferProgram, GasCycleLimit(100000)), [], initial)
  restoreFlatStream(foreign, retained)
  runFlat(foreign, 100)
  assert foreign.reason == StepError.InvalidPreparedProgram
  assert streamNodes(retained) == retainedNodes
  restoreFlatStream(second, retained)
  resetFlatFrame(second, initial)
  runFlat(second, 100)
  assert second.exit == StepExit.Panic and second.reason == StepError.None
  when not defined(pvmArm64JitRefuse):
    assert flatArmStatistics(second)[1] == 3
  # Whole-memory replacement keeps exact-plan native entries while discarding invocation-local bytes and registers.
  replaceFlatMemory(second, [], initial)
  runFlat(second, 100)
  assert second.exit == StepExit.Panic and second.reason == StepError.None
  when not defined(pvmArm64JitRefuse):
    assert flatArmStatistics(second)[0] == 1 and flatArmStatistics(second)[1] == 4
  let retired = flatArmStatistics(first)
  echo "RETIRED_STATS,", retired[0], ",", retired[1]
  assert retired[0] == 0 and retired[1] == 0
# A final arithmetic opcode lacking genuine fallthrough is refused at source admission, before JIT authority exists.
let truncatedProgram = captureOwner([@[200'u8, 0, 0], @[201'u8, 0, 0]])
echo "TRUNCATED_ADMISSION,", truncatedProgram.error
assert truncatedProgram.error == ProgramError.InvalidProgram

# Two-operation runs now deliberately remain interpreted; admission still preserves their exact values and exit.
let shortProgram = owner([@[200'u8, 0, 0], @[201'u8, 0, 0], @[0'u8]])
var shortFrame = newFlatFrame(newFlatPlan(shortProgram, GasCycleLimit(100000)), [], initial)
runFlat(shortFrame, 100)
assert shortFrame.reason == StepError.None and shortFrame.exit == StepExit.Panic
when defined(pvmArm64Jit):
  let short = flatArmStatistics(shortFrame)
  assert short[0] == 0 and short[1] == 0

when defined(pvmArm64Jit):
  var branchPredicates = 0
  for opcode in 0..255:
    if byte(opcode) notin {81'u8..90'u8, 170'u8..175'u8}: continue
    for pattern in [0'u8, 17, 128, 255]:
      var part = @[byte(opcode)]
      for position in 0..<24: part.add(pattern)
      let program = owner([part, @[0'u8]])
      let decoded = instruction(program, CodeAddress(0))
      assert decoded.error == ProgramError.None
      let slots = instructionRegisters(decoded)
      let low = uint64(decoded.value.x) and 0xffffffff'u64
      let immediate = if (low and 0x80000000'u64) != 0: low or 0xffffffff00000000'u64 else: low
      var native = default(ArmBlock)
      emitArmBranch(native, byte(opcode), slots, immediate, 0x12345678'u32, 0x76543210'u32)
      var words = armInstructions(native)
      let jit = newArmJit()
      assert armEntry(jit, 0, 1) == 0
      let published = publishArmEntry(jit, 0, 0, 1, words)
      when defined(pvmArm64JitRefuse):
        assert not published
      else:
        assert published
        for left in [0'u64, 1, 0x80000000'u64, 0xffffffff'u64, 0x7fffffffffffffff'u64,
            0x8000000000000000'u64, high(uint64)]:
          for right in [0'u64, 1, 0x80000000'u64, 0xffffffff'u64, 0x7fffffffffffffff'u64,
              0x8000000000000000'u64, high(uint64)]:
            var original = default(RegisterFile)
            original[slots.aIndex] = RegisterValue(left)
            original[slots.bIndex] = RegisterValue(right)
            let a = uint64(original[slots.aIndex])
            let b = if opcode <= 90: immediate else: uint64(original[slots.bIndex])
            let sa = a xor 0x8000000000000000'u64
            let sb = b xor 0x8000000000000000'u64
            let condition = case opcode
              of 81, 170: a == b
              of 82, 171: a != b
              of 83, 172: a < b
              of 84: a <= b
              of 85, 174: a >= b
              of 86: a > b
              of 87, 173: sa < sb
              of 88: sa <= sb
              of 89, 175: sa >= sb
              else: sa > sb
            let expected = if condition: 0x12345678'u32 else: 0x76543210'u32
            var registers = original
            assert callArmBranch(jit, 0, registers) == expected
            for slot in 0..<13: assert registers[slot] == original[slot]
            inc branchPredicates
  echo "ARM_BRANCH_PREDICATES,", branchPredicates

  # A full arena must retain the last valid entry after a failed replacement publication.
  let capacity = newArmJit()
  assert armEntry(capacity, 0, 1) == 0
  var pages = newSeq[uint32](1023)
  for position in 0..<pages.len: pages[position] = 0xd65f03c0'u32
  var initialWords = pages
  let admitted = publishArmEntry(capacity, 0, 77, 1, initialWords)
  when defined(pvmArm64JitRefuse):
    assert not admitted
  else:
    assert admitted
    var successes = 1
    while true:
      var next = pages
      if not publishArmEntry(capacity, 0, 77, 1, next): break
      inc successes
    assert successes == 256
    var capacityRegisters = default(RegisterFile)
    assert callArmEntry(capacity, 0, capacityRegisters) == 77
    echo "ARM_REPLACEMENT_REFUSAL,", successes

proc verifyControl(frame: var FlatFrame, program: Program, info: MachineInfo, budget: uint64) =
  ## Bounded single-step execution independently checks charged prefixes, target PCs and terminal normalization.
  let memory = captureMemory([], PageLimit(2)).value
  var expected = captureMachine(program, memory, info).value
  var exit = StepExit.Continued
  var reason = StepError.StepLimitExceeded
  var consumed = 0'u64
  var wantedHost = HostCallId(0)
  var wantedFault = PageAddress(0)
  var wantedHostPc = CodeAddress(0)
  for attempted in 0'u64..<budget:
    let attemptedPc = machineInfo(expected).value.pc
    let next = stepOnce(expected, GasCycleLimit(100000))
    assert next.error == StepError.None
    expected = next.value.machine
    exit = next.value.exit
    if exit != StepExit.OutOfGas: inc consumed
    if exit == StepExit.Host:
      # Psi_1 advances the published host PC; recursive suspension retains the attempted instruction.
      wantedHost = next.value.hostCall
      wantedHostPc = attemptedPc
    if exit == StepExit.Fault: wantedFault = next.value.faultPage
    if exit != StepExit.Continued:
      reason = StepError.None
      break
  resetFlatFrame(frame, info)
  runFlat(frame, budget)
  let wanted = machineInfo(expected).value
  if frame.reason != reason or frame.exit != exit:
    echo "CONTROL_EXIT,", budget, ",", reason, ",", exit, ",", frame.reason, ",", frame.exit
  assert frame.reason == reason and frame.exit == exit
  if frame.remaining != budget-consumed:
    echo "REMAINING,", budget, ",", consumed, ",", frame.remaining, ",", exit
  assert frame.remaining == budget-consumed
  if exit == StepExit.Host:
    assert frame.hostCall == wantedHost
  if exit == StepExit.Fault: assert frame.faultPage == wantedFault
  let pc = if exit in [StepExit.Halt, StepExit.Panic]: 0'u64
    elif exit == StepExit.Host: uint64(wantedHostPc)
    else: uint64(wanted.pc)
  if uint64(frame.info.pc) != pc: echo "CONTROL_PC,", uint64(frame.info.pc), ",", pc
  assert uint64(frame.info.pc) == pc
  assert frame.info.gas == wanted.gas and frame.info.gasDeficit == wanted.gasDeficit
  assert frame.info.blockCharged == wanted.blockCharged
  for slot in 0..<13: assert frame.info.registers[slot] == wanted.registers[slot]
  checkFlatSource(frame)

var controlCases = 0
for folded in [false, true]:
  var parts: seq[seq[byte]] = @[]
  if folded: parts.add(@[2'u8])
  for position in 0..<4:
    parts.add(@[149'u8, 0, 1])
    if folded and position == 0: parts.add(@[2'u8])
  let branchPc = if folded: 14'u32 else: 12'u32
  let backwards = 0'u32-branchPc
  var branch = @[172'u8, 0x10]
  for shift in 0..<4: branch.add(byte((backwards shr (shift*8)) and 255))
  parts.add(branch)
  parts.add(@[0'u8])
  let program = owner(parts)
  let plan = newFlatPlan(program, GasCycleLimit(100000))
  var registers = default(RegisterFile)
  registers[1] = RegisterValue(20)
  let warm = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: registers)
  var frame = newFlatFrame(plan, [], warm)
  verifyControl(frame, program, warm, 100)
  when defined(pvmArm64Jit):
    let counters = flatArmControlStatistics(frame)
    when defined(pvmArm64JitRefuse):
      assert counters[0] == 0 and counters[1] == 0
    else:
      assert counters[0] >= 4 and counters[1] >= 3
  for paid in [false, true]:
    for gas in [0'u64, 1, 4, 5, 6, 9, 10, 25, 26, 27, 1000, high(uint64)]:
      for budget in 0'u64..40'u64:
        let input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), registers: registers,
            blockCharged: paid)
        verifyControl(frame, program, input, budget)
        inc controlCases
  for policy in [0, 1]:
    # Explicit complete/lazy price owners must preserve the same native charge/quota observations as dynamic pricing.
    var priced = newFlatFrame(plan, [], warm)
    let complete = newGasPlan(program, GasPlanLimits(bytes: GasPlanByteLimit(65536),
        blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
    assert complete.error == GasPlanError.None
    let lazy = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(65536),
        cycles: GasCycleLimit(100000)))
    assert lazy.error == GasMemoError.None
    if policy == 0:
      assert selectFlatPrices(priced, complete.value, default(GasMemo)) == StepError.None
    else:
      assert selectFlatPrices(priced, default(GasPlan), lazy.value) == StepError.None
      assert gasMemoInfo(lazy.value).value.pricedBlocks == 0
      verifyControl(priced, program, warm, 0)
      assert gasMemoInfo(lazy.value).value.pricedBlocks == 0
      verifyControl(priced, program, warm, 1)
      assert gasMemoInfo(lazy.value).value.pricedBlocks == 1
    verifyControl(priced, program, warm, 100)
    when defined(pvmArm64Jit):
      let observed = flatArmControlStatistics(priced)
      when defined(pvmArm64JitRefuse):
        assert observed[0] == 0 and observed[1] == 0
      else:
        assert observed[0] >= 4 and observed[1] >= 3
    for paid in [false, true]:
      for gas in [0'u64, 1, 6, 7, 8, 35, 1000]:
        for budget in [0'u64, 1, 4, 5, 6, 7, 8, 34, 35, 36, 37, 100]:
          let input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), registers: registers,
              blockCharged: paid)
          verifyControl(priced, program, input, budget)
          inc controlCases
    if policy == 1: assert gasMemoInfo(lazy.value).value.pricedBlocks == 2
  # Transfer retains promoted headers and leaves with their exact plan; a new frame owns fresh CPU and budgets.
  var transferred = takeFlatStream(frame)
  var fresh = newFlatFrame(plan, [], warm)
  restoreFlatStream(fresh, transferred)
  verifyControl(fresh, program, warm, 100)
  when defined(pvmArm64Jit):
    let retired = flatArmControlStatistics(fresh)
    when defined(pvmArm64JitRefuse):
      assert retired[0] == 0 and retired[1] == 0
    else:
      assert retired[0] >= 9 and retired[1] >= 7
    assert flatArmControlStatistics(frame) == default(array[2, uint64])

echo "ARM_CONTROL_CASES,", controlCases

var boundaryCases = 0
for boundary in [0, 1]:
  var parts = @[@[149'u8, 0, 1], @[149'u8, 0, 1], @[149'u8, 0, 1], @[149'u8, 0, 1],
      @[172'u8, 0x10, 0xf4, 0xff, 0xff, 0xff]]
  if boundary == 0:
    # Native false continuation must arrive at the genuine checked ECALL with its exact source PC and identifier.
    parts.add(@[10'u8, 7])
  else:
    # An unmapped load must retain whole-block gas, exact page/PC and refund the unattempted trap reservation.
    parts.add(@[52'u8, 2, 1, 0, 1, 0])
  parts.add(@[0'u8])
  let program = owner(parts)
  var registers = default(RegisterFile)
  registers[1] = RegisterValue(20)
  let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: registers)
  var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), [], initial)
  verifyControl(frame, program, initial, 100)
  assert frame.exit == (if boundary == 0: StepExit.Host else: StepExit.Fault)
  when defined(pvmArm64Jit):
    let counters = flatArmControlStatistics(frame)
    when defined(pvmArm64JitRefuse):
      assert counters[0] == 0 and counters[1] == 0
    else:
      assert counters[0] >= 4 and counters[1] >= 3
  for gas in [0'u64, 1, 24, 25, 26, 27, 1000]:
    for budget in 0'u64..30'u64:
      let input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), registers: registers)
      verifyControl(frame, program, input, budget)
      inc boundaryCases
echo "ARM_HOST_FAULT_CASES,", boundaryCases

# A genuine host mapping replacement takes the slow reentry path without losing its live code capability.
let mappingProgram = owner([@[149'u8, 0, 1], @[149'u8, 0, 1], @[149'u8, 0, 1],
  @[149'u8, 0, 1], @[10'u8, 7], @[0'u8]])
var mappingFrame = newFlatFrame(newFlatPlan(mappingProgram, GasCycleLimit(100000)), [], initial)
runFlat(mappingFrame, 100)
assert mappingFrame.reason == StepError.None and mappingFrame.exit == StepExit.Host
let suspended = observeFlatHostMemory(mappingFrame)
var mapped = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
  bytes: default(array[4096, byte]))
mapped.bytes[17] = 123
let posterior = captureMemory([mapped], PageLimit(2))
assert posterior.error == MachineError.None
let resumedGas = mappingFrame.info.gas
let resumedRegisters = mappingFrame.info.registers
assert resumeFlatHostMemory(mappingFrame, posterior.value, resumedGas,
  resumedRegisters) == StepError.None
assert flatHostStats(mappingFrame)[1] == 1
runFlat(mappingFrame, 100)
assert mappingFrame.reason == StepError.None and mappingFrame.exit == StepExit.Panic
let published = flatMemorySnapshot(mappingFrame)
assert pageImage(published, mapped.index).value.bytes == mapped.bytes
assert memoryPageCount(suspended).value == PageCount(0)
resetFlatFrame(mappingFrame, initial)
runFlat(mappingFrame, 100)
assert mappingFrame.reason == StepError.None and mappingFrame.exit == StepExit.Host
when defined(pvmArm64Jit):
  let kept = flatArmStatistics(mappingFrame)
  when defined(pvmArm64JitRefuse):
    assert kept[0] == 0 and kept[1] == 0
  else:
    assert kept[0] == 1 and kept[1] == 2 and kept[2] == 8
echo "ARM_MAPPING_REENTRY,1"
