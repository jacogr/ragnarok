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
  var constantCases = 0
  for destination in 0..<13:
    # Each original decoded destination exercises actual emitted code; constants include high-halfword and negative values.
    var operand = @[20'u8, byte(destination)]
    for padding in 0..<23: operand.add(0'u8)
    let source = owner([operand, @[0'u8]])
    let decoded = instruction(source, CodeAddress(0))
    assert decoded.error == ProgramError.None, "constant decode"
    let slots = instructionRegisters(decoded)
    assert int(slots.destinationIndex) == destination, "constant decoded destination"
    var constants = @[0'u64, 1'u64, 65535'u64, 65536'u64,
      0x8000000000000000'u64, 0x0000123400000000'u64,
      0xffffffffffffffff'u64, 0xfffffffffffffffe'u64,
      0xffffffffffff1234'u64, 0x1234ffffffffffff'u64,
      0xffff0000ffff0000'u64, 0x123456789abcdef0'u64]
    for pattern in 0..<81:
      # Enumerate every four-halfword mixture of zero, ones and a nontrivial value independently of emitter policy.
      var digits = pattern
      var value = 0'u64
      for half in 0..<4:
        let part = case digits mod 3
          of 0: 0'u64
          of 1: 65535'u64
          else: 0x1234'u64
        value = value or (part shl (half*16))
        digits = digits div 3
      constants.add(value)
    let jit = newArmJit()
    assert armEntry(jit, 0, 1) == 0, "constant entry admission"
    for value in constants:
      # Poison all incoming registers; the selected slot must be defined in full and every other slot preserved.
      var fragment = default(ArmBlock)
      emitArmOperation(fragment, 20, slots, value)
      var words = armInstructions(fragment)
      assert words.len >= 2 and words.len <= 5, "constant word extent"
      let published = publishArmEntry(jit, 0, 1, 1, words)
      when defined(pvmArm64JitRefuse):
        assert not published
      else:
        assert published, "constant publication"
        var registers = default(RegisterFile)
        for slot in 0..<13: registers[slot] = RegisterValue(high(uint64)-uint64(slot))
        assert callArmEntry(jit, 0, registers) == 1, "constant continuation"
        for slot in 0..<13:
          let expected = RegisterValue(if slot == destination: value else: high(uint64)-uint64(slot))
          if registers[slot] != expected:
            echo "ARM_CONSTANT_VALUE,", destination, ",", value, ",", slot, ",", uint64(registers[
                slot]), ",", uint64(expected)
            assert false, "native constant value"
      inc constantCases
  echo "ARM_CONSTANT_CASES,", constantCases

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

proc verifyControl(frame: var FlatFrame, program: Program, info: MachineInfo, budget: uint64,
    images: openArray[PageImage] = []) =
  ## Bounded single-step execution independently checks charged prefixes, target PCs and terminal normalization.
  let memory = captureMemory(images, PageLimit(uint32(max(2, images.len)))).value
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
  if images.len != 0:
    # Load-only work must preserve all private bytes and permission metadata, including inaccessible pages.
    let published = flatMemorySnapshot(frame)
    for image in images:
      let actual = pageImage(published, image.index)
      assert actual.error == MachineError.None
      assert actual.value.access == image.access and actual.value.bytes == image.bytes

var loadCases = 0
for layout in 0..<8:
  var images: seq[PageImage] = @[]
  if layout != 0:
    # Adjacent RO/RW, split permissions, a missing page, an inaccessible page, fragmented RO and the final page.
    var first = PageImage(index: PageIndex(if layout == 7: 1048575'u32 else: 16'u32),
        access: (if layout == 2 or layout == 7: PageAccess.ReadWrite else: PageAccess.ReadOnly),
        bytes: default(array[4096, byte]))
    for at in 0..<4096: first.bytes[at] = byte((at*17+layout) mod 256)
    images.add(first)
    if layout in [1, 2, 3, 4, 6]:
      var second = PageImage(index: PageIndex(if layout == 6: 18'u32 else: 17'u32),
          access: (if layout == 4: PageAccess.Inaccessible elif layout in [2,
              3]: PageAccess.ReadWrite else: PageAccess.ReadOnly),
          bytes: default(array[4096, byte]))
      if second.access != PageAccess.Inaccessible:
        for at in 0..<4096: second.bytes[at] = byte((at*29+layout+91) mod 256)
      images.add(second)
  for destination in [0, 1]:
    for displacement in [0'u32, 7'u32, 0xfffffff8'u32]:
      # A aliases B in one shape; source address calculation must finish before the loaded destination changes.
      var load = @[130'u8, byte(0x10+destination)]
      for shift in 0..<4: load.add(byte((uint64(displacement) shr (shift*8)) and 255))
      let program = owner([load, @[149'u8, byte(destination*16+2), 1],
          @[133'u8, 0x23, 0x7f], @[149'u8, 0x34, 0xff], @[0'u8]])
      let plan = newFlatPlan(program, GasCycleLimit(100000))
      let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
      var frame = newFlatFrame(plan, images, initial)
      for address in [0'u64, 65535, 65536, 65537, 69624, 69625, 69631, 69632, 73720, 73721,
          73728, 0xfffffff7'u64, 0xfffffff8'u64, 0xffffffff'u64, 0x100010000'u64, high(uint64)]:
        var input = initial
        for slot in 0..<13: input.registers[slot] = RegisterValue(0x923456789abcdef0'u64+uint64(slot))
        input.registers[1] = RegisterValue(address)
        verifyControl(frame, program, input, 9, images)
        inc loadCases
      for paid in [false, true]:
        for gas in [0'u64, 1, 4, 5, 1000]:
          for budget in 0'u64..6'u64:
            # Reuse an already emitted cache around exact out-of-gas and every partial reservation boundary.
            var input = initial
            input.registers[1] = RegisterValue(if layout == 7: 0xfffff003'u64 else: 65539'u64)
            input.gas = MachineGas(gas)
            input.blockCharged = paid
            verifyControl(frame, program, input, budget, images)
            inc loadCases
      when defined(pvmArm64Jit):
        let stats = flatArmStatistics(frame)
        when defined(pvmArm64JitRefuse):
          assert stats[2] == 0
        else:
          # The rejected head-load leaf is absent; three trailing operations retain the accepted floor.
          assert stats[2] == 0
      # Same-plan replacement and a transferred stream must read the new invocation's word.
      var changed: seq[PageImage] = @[]
      for original in images:
        var image = original
        if image.access != PageAccess.Inaccessible:
          for at in 0..<4096: image.bytes[at] = byte((at*31+layout+7) mod 256)
        changed.add(image)
      let accepted = replaceFlatMemoryChecked(frame, changed, initial)
      assert accepted == FlatError.None
      var input = initial
      input.registers[1] = RegisterValue(if layout == 7: 0xfffff003'u64 else: 65539'u64)
      verifyControl(frame, program, input, 9, changed)
      var cache = takeFlatStream(frame)
      var fresh = newFlatFrame(plan, images, input)
      restoreFlatStream(fresh, cache)
      verifyControl(fresh, program, input, 9, images)
      loadCases+=2

# Folded source instructions and all three price policies retain the same exact head-load reservation semantics.
for folded in [false, true]:
  var parts = @[@[130'u8, 0x10, 0, 0, 0, 0]]
  if folded: parts.add(@[2'u8])
  parts.add(@[149'u8, 0x02, 1])
  parts.add(@[133'u8, 0x23, 0x7f])
  parts.add(@[149'u8, 0x34, 0xff])
  parts.add(@[0'u8])
  let program = owner(parts)
  var image = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
      bytes: default(array[4096, byte]))
  for at in 0..<4096: image.bytes[at] = byte((at*43+17) mod 256)
  var input = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
  input.registers[1] = RegisterValue(65539)
  for policy in 0..<3:
    var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(100000)), [image], input)
    if policy == 1:
      let complete = newGasPlan(program, GasPlanLimits(bytes: GasPlanByteLimit(65536),
          blocks: GasPlanBlockLimit(1024), cycles: GasCycleLimit(100000)))
      assert complete.error == GasPlanError.None
      assert selectFlatPrices(frame, complete.value, default(GasMemo)) == StepError.None
    elif policy == 2:
      let lazy = newGasMemo(program, GasMemoLimits(bytes: GasMemoByteLimit(65536),
          cycles: GasCycleLimit(100000)))
      assert lazy.error == GasMemoError.None
      assert selectFlatPrices(frame, default(GasPlan), lazy.value) == StepError.None
      verifyControl(frame, program, input, 0, [image])
      assert gasMemoInfo(lazy.value).value.pricedBlocks == 0
      verifyControl(frame, program, input, 1, [image])
      assert gasMemoInfo(lazy.value).value.pricedBlocks == 1
    for paid in [false, true]:
      for gas in [0'u64, 1, 4, 5, 6, 1000]:
        for budget in 0'u64..7'u64:
          var bounded = input
          bounded.gas = MachineGas(gas)
          bounded.blockCharged = paid
          verifyControl(frame, program, bounded, budget, [image])
          inc loadCases

echo "ARM_HEAD_LOAD_CASES,", loadCases

# A host call changes the map before a static jump revisits the same checked load.
let loadLoop = owner([@[130'u8, 0x10, 0, 0, 0, 0], @[149'u8, 0x02, 1],
  @[133'u8, 0x23, 0x7f], @[149'u8, 0x34, 0xff], @[10'u8, 7],
  @[40'u8, 0xef, 0xff, 0xff, 0xff]])
var firstWord = PageImage(index: PageIndex(16), access: PageAccess.ReadOnly,
    bytes: default(array[4096, byte]))
for at in 0..<4096: firstWord.bytes[at] = byte((at*7+19) mod 256)
var loadInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
loadInfo.registers[1] = RegisterValue(65539)
var hostLoadFrame = newFlatFrame(newFlatPlan(loadLoop, GasCycleLimit(100000)), [firstWord], loadInfo)
runFlat(hostLoadFrame, 100)
assert hostLoadFrame.reason == StepError.None and hostLoadFrame.exit == StepExit.Host
let originalHostMemory = observeFlatHostMemory(hostLoadFrame)
var secondWord = firstWord
for at in 0..<4096: secondWord.bytes[at] = byte((at*13+71) mod 256)
let changedHostMemory = captureMemory([secondWord], PageLimit(2)).value
let changedGas = hostLoadFrame.info.gas
let changedRegisters = hostLoadFrame.info.registers
assert resumeFlatHostMemory(hostLoadFrame, changedHostMemory, changedGas,
    changedRegisters) == StepError.None
let resumedLoadInfo = hostLoadFrame.info
verifyControl(hostLoadFrame, loadLoop, resumedLoadInfo, 6, [secondWord])
when defined(pvmArm64Jit):
  let partialLoadStats = flatArmStatistics(hostLoadFrame)
  when defined(pvmArm64JitRefuse): assert partialLoadStats[2] == 0
  else: assert partialLoadStats[1] == 0 and partialLoadStats[2] == 0
# Include the jump and the complete six-instruction target block, even though its host exit refunds the final jump.
verifyControl(hostLoadFrame, loadLoop, resumedLoadInfo, 7, [secondWord])
assert hostLoadFrame.exit == StepExit.Host and flatHostStats(hostLoadFrame)[1] == 1
assert pageImage(originalHostMemory, PageIndex(16)).value.bytes == firstWord.bytes
when defined(pvmArm64Jit):
  let beforeUnmapping = flatArmStatistics(hostLoadFrame)
  when defined(pvmArm64JitRefuse): assert beforeUnmapping[2] == 0
  else: assert beforeUnmapping[0] == 0 and beforeUnmapping[1] == 0 and beforeUnmapping[2] == 0
  discard observeFlatHostMemory(hostLoadFrame)
  let absentHostMemory = captureMemory([], PageLimit(2)).value
  let unmappedGas = hostLoadFrame.info.gas
  let unmappedRegisters = hostLoadFrame.info.registers
  assert resumeFlatHostMemory(hostLoadFrame, absentHostMemory, unmappedGas,
      unmappedRegisters) == StepError.None
  let unmappedLoadInfo = hostLoadFrame.info
  verifyControl(hostLoadFrame, loadLoop, unmappedLoadInfo, 7)
  assert hostLoadFrame.exit == StepExit.Fault
  assert flatArmStatistics(hostLoadFrame) == beforeUnmapping

echo "ARM_HEAD_HOST_MAP,1"

var controlCases = 0
# Both formerly excluded short suffixes and the accepted four-operation shape retain all boundary checks.
for arithmeticCount in [1, 2, 3, 4]:
  for folded in [false, true]:
    var parts: seq[seq[byte]] = @[]
    if folded: parts.add(@[2'u8])
    for position in 0..<arithmeticCount:
      parts.add(@[149'u8, 0, 1])
      if folded and position == 0: parts.add(@[2'u8])
    let branchPc = uint32(arithmeticCount*3+(if folded: 2 else: 0))
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
