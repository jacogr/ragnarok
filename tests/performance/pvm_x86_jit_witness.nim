# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Native x86 scalar/alias equivalence, every source prefix and honest OS-refusal witnesses.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, gas, step, registers]
import ../../src/pvm/internal/[handler_stream, x86_jit]

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

var literalCases = 0
for opcode in 0..255:
  if not supportedX86Opcode(byte(opcode)): continue
  for pattern in [0'u8, 17, 128, 255]:
    var part = @[byte(opcode)]
    for position in 0..<24: part.add(pattern)
    let program = owner([part, part, part, part, @[0'u8]])
    let plan = newFlatPlan(program, GasCycleLimit(100000))
    for seed in [0'u64, 31, 32, 63, 64, 127, 0x80000000'u64, 0xffffffff'u64,
        0x8000000000000000'u64, high(uint64)]:
      var original = default(RegisterFile)
      for slot in 0..<13: original[slot] = RegisterValue(seed xor uint64(slot))
      var expected = original
      for instruction in 0..<4:
        # The portable evaluator never emits or calls native code; all source aliases are decoded independently.
        let evaluated = evaluateRegisters(program, CodeAddress(uint32(instruction*25)), expected)
        assert evaluated.error == RegisterError.None
        expected = evaluated.value
      var frame = newFlatFrame(plan, [], MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000),
          registers: original))
      runFlat(frame, 100)
      assert frame.reason == StepError.None and frame.exit == StepExit.Panic
      assert frame.info.registers == expected, "x86 scalar lowering differs from portable evaluator"
      let stats = flatX86Statistics(frame)
      when defined(pvmX86JitRefuse): assert stats[0] == 0 and stats[1] == 0 and stats[2] == 0
      else: assert stats[0] == 1 and stats[1] == 1 and stats[2] == 4
      inc literalCases
stdout.writeLine("X86_REGISTER_CASES," & $literalCases)

# Frozen arbitrary-precision integer equations: A, B, signed/signed, unsigned/unsigned, signed/unsigned upper words.
# One arithmetic result is followed only by identity moves; later products cannot erase an earlier wrong answer.
const highProducts = [
  [0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000000'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000000'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000000'u64, 0x7fffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000000'u64, 0x8000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000000'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000000'u64, 0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000000'u64, 0xdeadbeef12345678'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000000'u64, 0x0000000080000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0x7fffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0x8000000000000000'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0xdeadbeef12345678'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000001'u64, 0x0000000080000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000002'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000002'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000002'u64, 0x7fffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000002'u64, 0x8000000000000000'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
      0x0000000000000001'u64],
  [0x0000000000000002'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
      0x0000000000000001'u64],
  [0x0000000000000002'u64, 0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000000000002'u64, 0xdeadbeef12345678'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
      0x0000000000000001'u64],
  [0x0000000000000002'u64, 0x0000000080000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x7fffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x7fffffffffffffff'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x7fffffffffffffff'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x7fffffffffffffff'u64, 0x7fffffffffffffff'u64, 0x3fffffffffffffff'u64, 0x3fffffffffffffff'u64,
      0x3fffffffffffffff'u64],
  [0x7fffffffffffffff'u64, 0x8000000000000000'u64, 0xc000000000000000'u64, 0x3fffffffffffffff'u64,
      0x3fffffffffffffff'u64],
  [0x7fffffffffffffff'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x7ffffffffffffffe'u64,
      0x7ffffffffffffffe'u64],
  [0x7fffffffffffffff'u64, 0x0000000100000001'u64, 0x0000000080000000'u64, 0x0000000080000000'u64,
      0x0000000080000000'u64],
  [0x7fffffffffffffff'u64, 0xdeadbeef12345678'u64, 0xef56df77891a2b3c'u64, 0x6f56df77891a2b3b'u64,
      0x6f56df77891a2b3b'u64],
  [0x7fffffffffffffff'u64, 0x0000000080000000'u64, 0x000000003fffffff'u64, 0x000000003fffffff'u64,
      0x000000003fffffff'u64],
  [0x8000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x8000000000000000'u64, 0x0000000000000001'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
      0xffffffffffffffff'u64],
  [0x8000000000000000'u64, 0x0000000000000002'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
      0xffffffffffffffff'u64],
  [0x8000000000000000'u64, 0x7fffffffffffffff'u64, 0xc000000000000000'u64, 0x3fffffffffffffff'u64,
      0xc000000000000000'u64],
  [0x8000000000000000'u64, 0x8000000000000000'u64, 0x4000000000000000'u64, 0x4000000000000000'u64,
      0xc000000000000000'u64],
  [0x8000000000000000'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64, 0x7fffffffffffffff'u64,
      0x8000000000000000'u64],
  [0x8000000000000000'u64, 0x0000000100000001'u64, 0xffffffff7fffffff'u64, 0x0000000080000000'u64,
      0xffffffff7fffffff'u64],
  [0x8000000000000000'u64, 0xdeadbeef12345678'u64, 0x10a9208876e5d4c4'u64, 0x6f56df77891a2b3c'u64,
      0x90a9208876e5d4c4'u64],
  [0x8000000000000000'u64, 0x0000000080000000'u64, 0xffffffffc0000000'u64, 0x0000000040000000'u64,
      0xffffffffc0000000'u64],
  [0xffffffffffffffff'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0xffffffffffffffff'u64, 0x0000000000000001'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
      0xffffffffffffffff'u64],
  [0xffffffffffffffff'u64, 0x0000000000000002'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
      0xffffffffffffffff'u64],
  [0xffffffffffffffff'u64, 0x7fffffffffffffff'u64, 0xffffffffffffffff'u64, 0x7ffffffffffffffe'u64,
      0xffffffffffffffff'u64],
  [0xffffffffffffffff'u64, 0x8000000000000000'u64, 0x0000000000000000'u64, 0x7fffffffffffffff'u64,
      0xffffffffffffffff'u64],
  [0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64, 0xfffffffffffffffe'u64,
      0xffffffffffffffff'u64],
  [0xffffffffffffffff'u64, 0x0000000100000001'u64, 0xffffffffffffffff'u64, 0x0000000100000000'u64,
      0xffffffffffffffff'u64],
  [0xffffffffffffffff'u64, 0xdeadbeef12345678'u64, 0x0000000000000000'u64, 0xdeadbeef12345677'u64,
      0xffffffffffffffff'u64],
  [0xffffffffffffffff'u64, 0x0000000080000000'u64, 0xffffffffffffffff'u64, 0x000000007fffffff'u64,
      0xffffffffffffffff'u64],
  [0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000100000001'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000100000001'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000100000001'u64, 0x7fffffffffffffff'u64, 0x0000000080000000'u64, 0x0000000080000000'u64,
      0x0000000080000000'u64],
  [0x0000000100000001'u64, 0x8000000000000000'u64, 0xffffffff7fffffff'u64, 0x0000000080000000'u64,
      0x0000000080000000'u64],
  [0x0000000100000001'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x0000000100000000'u64,
      0x0000000100000000'u64],
  [0x0000000100000001'u64, 0x0000000100000001'u64, 0x0000000000000001'u64, 0x0000000000000001'u64,
      0x0000000000000001'u64],
  [0x0000000100000001'u64, 0xdeadbeef12345678'u64, 0xffffffffdeadbeee'u64, 0x00000000deadbeef'u64,
      0x00000000deadbeef'u64],
  [0x0000000100000001'u64, 0x0000000080000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0xdeadbeef12345678'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0xdeadbeef12345678'u64, 0x0000000000000001'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64,
      0xffffffffffffffff'u64],
  [0xdeadbeef12345678'u64, 0x0000000000000002'u64, 0xffffffffffffffff'u64, 0x0000000000000001'u64,
      0xffffffffffffffff'u64],
  [0xdeadbeef12345678'u64, 0x7fffffffffffffff'u64, 0xef56df77891a2b3c'u64, 0x6f56df77891a2b3b'u64,
      0xef56df77891a2b3c'u64],
  [0xdeadbeef12345678'u64, 0x8000000000000000'u64, 0x10a9208876e5d4c4'u64, 0x6f56df77891a2b3c'u64,
      0xef56df77891a2b3c'u64],
  [0xdeadbeef12345678'u64, 0xffffffffffffffff'u64, 0x0000000000000000'u64, 0xdeadbeef12345677'u64,
      0xdeadbeef12345678'u64],
  [0xdeadbeef12345678'u64, 0x0000000100000001'u64, 0xffffffffdeadbeee'u64, 0x00000000deadbeef'u64,
      0xffffffffdeadbeee'u64],
  [0xdeadbeef12345678'u64, 0xdeadbeef12345678'u64, 0x04564f341cb0720d'u64, 0xc1b1cd1241191efd'u64,
      0xe3040e232ee4c885'u64],
  [0xdeadbeef12345678'u64, 0x0000000080000000'u64, 0xffffffffef56df77'u64, 0x000000006f56df77'u64,
      0xffffffffef56df77'u64],
  [0x0000000080000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000080000000'u64, 0x0000000000000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000080000000'u64, 0x0000000000000002'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000080000000'u64, 0x7fffffffffffffff'u64, 0x000000003fffffff'u64, 0x000000003fffffff'u64,
      0x000000003fffffff'u64],
  [0x0000000080000000'u64, 0x8000000000000000'u64, 0xffffffffc0000000'u64, 0x0000000040000000'u64,
      0x0000000040000000'u64],
  [0x0000000080000000'u64, 0xffffffffffffffff'u64, 0xffffffffffffffff'u64, 0x000000007fffffff'u64,
      0x000000007fffffff'u64],
  [0x0000000080000000'u64, 0x0000000100000001'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
  [0x0000000080000000'u64, 0xdeadbeef12345678'u64, 0xffffffffef56df77'u64, 0x000000006f56df77'u64,
      0x000000006f56df77'u64],
  [0x0000000080000000'u64, 0x0000000080000000'u64, 0x0000000000000000'u64, 0x0000000000000000'u64,
      0x0000000000000000'u64],
]
var highLiteralCases = 0
for opcode in 213'u8..217'u8:
  for alias in [[0, 1, 2], [0, 1, 0], [0, 1, 1], [1, 0, 0], [1, 0, 1], [12, 12, 12]]:
    # Each source/destination shape publishes once, then consumes fresh values without retaining their addresses.
    let program = owner([@[opcode, byte(alias[0]+alias[1]*16), byte(alias[2])],
        @[100'u8, 0xcc], @[100'u8, 0xcc], @[100'u8, 0xcc], @[0'u8]])
    let decoded = instruction(program, CodeAddress(0))
    let identity = instruction(program, CodeAddress(3))
    assert decoded.error == ProgramError.None and identity.error == ProgramError.None
    let slots = instructionRegisters(decoded)
    let jit = newX86Jit()
    assert x86Entry(jit, 0, 4) == 0
    var fragment = default(X86Block)
    emitX86Operation(fragment, opcode, slots, 0)
    for index in 0..<3:
      # The qualifying four-operation leaf keeps every bit of the tested arithmetic result observable.
      emitX86Operation(fragment, 100, instructionRegisters(identity), 0)
    let published = publishX86Entry(jit, 0, 4, 4, fragment)
    when defined(pvmX86JitRefuse): assert not published
    else: assert published
    for vector in highProducts:
      # Equal source coordinates require one original value; unequal literal pairs use distinct sources.
      if alias[0] == alias[1] and vector[0] != vector[1]: continue
      var registers = default(RegisterFile)
      for index in 0..<13: registers[index] = RegisterValue(0x55aa00ff12340000'u64+uint64(index))
      registers[slots.aIndex] = RegisterValue(vector[0])
      registers[slots.bIndex] = RegisterValue(vector[1])
      let original = registers
      let expected = if opcode <= 215: vector[int(opcode)-211]
        elif opcode == 216: uint64(vector[0] < vector[1])
        else: uint64((vector[0] xor 0x8000000000000000'u64) < (vector[
            1] xor 0x8000000000000000'u64))
      when not defined(pvmX86JitRefuse):
        # Independent literals check the first result, its complete alias behavior and all untouched registers.
        assert callX86Entry(jit, 0, registers) == 4
        for index in 0..<13:
          let wanted = if index == int(slots.destinationIndex): RegisterValue(
              expected) else: original[index]
          assert registers[index] == wanted, "x86 independent high-product/comparison literal"
      inc highLiteralCases
stdout.writeLine("X86_HIGH_LITERAL_CASES," & $highLiteralCases)

var prefixCases = 0
for depth in [3, 4, 5, 16, 63, 64, 65, 129]:
  var parts: seq[seq[byte]] = @[]
  for instruction in 0..<depth: parts.add(@[149'u8, 0x00, 1])
  parts.add(@[0'u8])
  let program = owner(parts)
  let nativePlan = newFlatPlan(program, GasCycleLimit(100000))
  var captured = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
  assert captured.error == FlatError.None
  let plainPlan = takeValue(captured)
  for gas in [0'u64, uint64(depth), uint64(depth+1), high(uint64)]:
    for paid in [false, true]:
      for budget in 0..depth+2:
        # Complete CPU/gas/source-attempt state agrees at every prefix, including leaf and block caps.
        let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(gas), blockCharged: paid,
            registers: default(RegisterFile))
        var plain = newFlatFrame(plainPlan, [], info)
        var native = newFlatFrame(nativePlan, [], info)
        runFlat(plain, uint64(budget))
        runFlat(native, uint64(budget))
        assert native.reason == plain.reason and native.exit == plain.exit
        assert native.remaining == plain.remaining
        checkFlatSource(native)
        checkFlatSource(plain)
        assert native.info.pc == plain.info.pc and native.info.gas == plain.info.gas
        assert native.info.registers == plain.info.registers
        assert native.info.blockCharged == plain.info.blockCharged
        assert native.info.gasDeficit == plain.info.gasDeficit
        assert flatX86Statistics(plain)[2] == 0
        inc prefixCases
stdout.writeLine("X86_PREFIX_CASES," & $prefixCases)

# A cache moves only with its exact immutable plan; a new invocation must borrow fresh register bytes.
let reuseProgram = owner([@[149'u8, 0x00, 1], @[149'u8, 0x00, 1], @[149'u8, 0x00, 1],
    @[149'u8, 0x00, 1], @[0'u8]])
let reusePlan = newFlatPlan(reuseProgram, GasCycleLimit(100))
var first = newFlatFrame(reusePlan, [], MachineInfo(pc: CodeAddress(0), gas: MachineGas(100),
    registers: default(RegisterFile)))
runFlat(first, 10)
var stream = takeFlatStream(first)
var info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(100), registers: default(RegisterFile))
info.registers[0] = RegisterValue(900)
var second = newFlatFrame(reusePlan, [], info)
restoreFlatStream(second, stream)
runFlat(second, 10)
assert uint64(second.info.registers[0]) == 904
let retained = flatX86Statistics(second)
when defined(pvmX86JitRefuse): assert retained[0] == 0 and retained[1] == 0 and retained[2] == 0
else: assert retained[0] == 1 and retained[1] == 2 and retained[2] == 8
stdout.writeLine("X86_CACHE_REUSE_OK")


var branchLiteralCases = 0
let identityProgram = owner([@[100'u8, 0xcc], @[0'u8]])
let identitySlots = instructionRegisters(instruction(identityProgram, CodeAddress(0)))
for opcode in 0..255:
  if byte(opcode) notin {81'u8..90, 170..175}: continue
  let part = if opcode <= 90: @[byte(opcode), 0x10, 0, 0, 0, 0, 0]
    else: @[byte(opcode), 0x10, 0, 0, 0, 0]
  let program = owner([part, @[0'u8]])
  let slots = instructionRegisters(instruction(program, CodeAddress(0)))
  for vector in highProducts:
    # Immediate branches compare the Gray Paper's signed low-word extension; register branches retain all64bits.
    let right = if opcode > 90: vector[1]
      elif (vector[1] and 0x80000000'u64) != 0: (vector[1] and 0xffffffff'u64) or 0xffffffff00000000'u64
      else: vector[1] and 0xffffffff'u64
    let left = vector[0]
    let lessSigned = (left xor 0x8000000000000000'u64) < (right xor 0x8000000000000000'u64)
    let greaterSigned = (left xor 0x8000000000000000'u64) > (right xor 0x8000000000000000'u64)
    let taken = case opcode
      of 81, 170: left == right
      of 82, 171: left != right
      of 83, 172: left < right
      of 84: left <= right
      of 85, 174: left >= right
      of 86: left > right
      of 87, 173: lessSigned
      of 88: not greaterSigned
      of 89, 175: not lessSigned
      else: greaterSigned
    let jit = newX86Jit()
    discard x86Entry(jit, 0, 8)
    var arithmetic = default(X86Block)
    for instruction in 0..<4: emitX86Operation(arithmetic, 100, identitySlots, 0)
    let first = publishX86Entry(jit, 0, 4, 4, arithmetic)
    var control = default(X86Block)
    for instruction in 0..<4: emitX86Operation(control, 100, identitySlots, 0)
    emitX86Branch(control, byte(opcode), slots, right, 6, 7)
    let promoted = publishX86Entry(jit, 0, 4, 5, control, conditional = true)
    when defined(pvmX86JitRefuse): assert not first and not promoted
    else:
      # Returned values are scalar stream coordinates; comparison/selection must not write any guest register.
      assert first and promoted
      var registers = default(RegisterFile)
      for index in 0..<13: registers[index] = RegisterValue(uint64(index)+100)
      registers[slots.aIndex] = RegisterValue(left)
      if opcode > 90: registers[slots.bIndex] = RegisterValue(right)
      let original = registers
      assert callX86Branch(jit, 0, registers) == (if taken: 6'u32 else: 7'u32)
      assert registers == original
      assert jit.branchCalls == 1 and jit.operations == 5
    inc branchLiteralCases
stdout.writeLine("X86_BRANCH_LITERAL_CASES," & $branchLiteralCases)

# A short ordinary charged block loops through a positive cached conditional, then reaches a genuine panic instruction.
let branchProgram = owner([@[149'u8, 0, 1], @[172'u8, 0x10, 0xfd, 0xff, 0xff, 0xff], @[0'u8]])
let branchPlan = newFlatPlan(branchProgram, GasCycleLimit(100000))
var interpretedCapture = prepareFlatPlan(branchProgram, GasCycleLimit(100000), defaultFlatLimits(), false)
assert interpretedCapture.error == FlatError.None
let interpretedPlan = takeValue(interpretedCapture)
var warmInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
warmInfo.registers[1] = RegisterValue(32)
var branchFrame = newFlatFrame(branchPlan, [], warmInfo)
var interpretedFrame = newFlatFrame(interpretedPlan, [], warmInfo)
for visit in 0..<2:
  # Warming the same exact owner must resolve both destinations and execute the compiled whole-block path.
  resetFlatFrame(branchFrame, warmInfo)
  runFlat(branchFrame, 1000)
  assert branchFrame.reason == StepError.None and branchFrame.exit == StepExit.Panic
when defined(pvmX86JitRefuse): assert flatX86ControlStatistics(branchFrame) == default(array[2, uint64])
else:
  let control = flatX86ControlStatistics(branchFrame)
  assert control[0] > 0 and control[1] > 0
var branchPrefixCases = 0
for initial in [0'u64, 5, 31]:
  for paid in [false, true]:
    for gas in [0'u64, 1, 2, 3, 4, 5, 64, 65, high(uint64)]:
      for budget in [0'u64, 1, 2, 3, 4, 5, 63, 64, 65, 100]:
        # Reused native blocks retain exact source-attempt, gas, exit-PC, paid-state and register behavior at every boundary.
        var info = warmInfo
        info.registers[0] = RegisterValue(initial)
        info.blockCharged = paid
        info.gas = MachineGas(gas)
        resetFlatFrame(branchFrame, info)
        resetFlatFrame(interpretedFrame, info)
        runFlat(branchFrame, budget)
        runFlat(interpretedFrame, budget)
        assert branchFrame.reason == interpretedFrame.reason and branchFrame.exit ==
            interpretedFrame.exit
        assert branchFrame.remaining == interpretedFrame.remaining
        assert branchFrame.info.pc == interpretedFrame.info.pc
        assert branchFrame.info.gas == interpretedFrame.info.gas
        assert branchFrame.info.gasDeficit == interpretedFrame.info.gasDeficit
        assert branchFrame.info.blockCharged == interpretedFrame.info.blockCharged
        assert branchFrame.info.registers == interpretedFrame.info.registers
        checkFlatSource(branchFrame)
        checkFlatSource(interpretedFrame)
        inc branchPrefixCases
stdout.writeLine("X86_BRANCH_PREFIX_CASES," & $branchPrefixCases)


# Both charged blocks have positively cached scalar arms; the second returns to the first or exits to a real panic.
let pairedProgram = owner([@[149'u8, 0, 1], @[172'u8, 0x10, 6, 0, 0, 0],
    @[149'u8, 2, 1], @[172'u8, 0x10, 0xf4, 0xff, 0xff, 0xff], @[0'u8]])
var regionCases = 0
for paired in [false, true]:
  # Use independently admitted interpreted owners; a cached native region cannot turn its own result into the oracle.
  let program = if paired: pairedProgram else: branchProgram
  let nativePlan = newFlatPlan(program, GasCycleLimit(100000))
  var checkedCapture = prepareFlatPlan(program, GasCycleLimit(100000), defaultFlatLimits(), false)
  assert checkedCapture.error == FlatError.None
  let checkedPlan = takeValue(checkedCapture)
  var nativeFrame = newFlatFrame(nativePlan, [], warmInfo)
  var checkedFrame = newFlatFrame(checkedPlan, [], warmInfo)
  for visit in 0..<3:
    # Reused source caches must discover and execute a real closed loop before boundary cases can count as native evidence.
    resetFlatFrame(nativeFrame, warmInfo)
    runFlat(nativeFrame, 1000)
    assert nativeFrame.reason == StepError.None and nativeFrame.exit == StepExit.Panic
  when defined(pvmX86JitRefuse):
    assert flatX86RegionStatistics(nativeFrame) == default(array[2, uint64])
  else:
    let connected = flatX86RegionStatistics(nativeFrame)
    assert connected[0] > 0 and connected[1] > connected[0]
  for initial in [0'u64, 5, 31]:
    for paid in [false, true]:
      for gas in [0'u64, 1, 2, 3, 4, 5, 63, 64, 65, high(uint64)]:
        for budget in [0'u64, 1, 2, 3, 4, 5, 63, 64, 65, 127, 128, 129]:
          # Guard exits at either block retain precise original gas, source prefix, paid state and immutable source snapshots.
          var info = warmInfo
          info.registers[0] = RegisterValue(initial)
          info.blockCharged = paid
          info.gas = MachineGas(gas)
          resetFlatFrame(nativeFrame, info)
          resetFlatFrame(checkedFrame, info)
          runFlat(nativeFrame, budget)
          runFlat(checkedFrame, budget)
          assert nativeFrame.reason == checkedFrame.reason and nativeFrame.exit == checkedFrame.exit
          assert nativeFrame.remaining == checkedFrame.remaining
          assert nativeFrame.info.pc == checkedFrame.info.pc
          assert nativeFrame.info.gas == checkedFrame.info.gas
          assert nativeFrame.info.gasDeficit == checkedFrame.info.gasDeficit
          assert nativeFrame.info.blockCharged == checkedFrame.info.blockCharged
          assert nativeFrame.info.registers == checkedFrame.info.registers
          checkFlatSource(nativeFrame)
          checkFlatSource(checkedFrame)
          inc regionCases
stdout.writeLine("X86_REGION_PREFIX_CASES," & $regionCases)

proc checkRegionContext(addSlots, compareSlots: RegisterSlots, resident: int): int =
  ## One independent scalar oracle covers every complete/partial block, including zero-block publication of each cached guest coordinate.
  assert resident >= -1 and resident <= 12
  result = 0
  for active in 1..2:
    # Publish a real ordinary leaf first so the independently owned arena has genuine executable storage.
    let jit = newX86Jit()
    discard x86Entry(jit, 0, 32)
    var warm = default(X86Block)
    for operation in 0..<4: emitX86Operation(warm, 149, addSlots, 1)
    assert publishX86Entry(jit, 0, 4, 4, warm)
    var blocks = default(array[2, X86RegionBlock])
    for index in 0..<active:
      # Both blocks increment R0 and branch on R0<R1, with distinct gas prices and original header coordinates.
      let header = uint32(7+index)
      let following = if active == 1 or index == 1: 7'u32 else: 8'u32
      var body = default(X86Block)
      if resident >= 0: body = newX86ResidentBlock(range[0..12](resident))
      emitX86Operation(body, 149, addSlots, 1)
      emitX86Branch(body, 172, compareSlots, 0, following, 10)
      blocks[index] = X86RegionBlock(header: header, span: 2, operations: 2,
        price: uint64(3+index*2), yes: following, no: 10, body: move(body))
    assert publishX86Region(jit, blocks, range[1..2](active))
    for initial in [0'u64, 4, 99, high(uint64)]:
      for gas in [0'u64, 1, 2, 3, 4, 5, 8, 16, high(uint64)]:
        for quota in [0'u64, 1, 2, 3, 4, 5, 10, 63, 64, high(uint64)]:
          for sentinel in [0xffffffff'u64, 0xfedcba9876543210'u64]:
            # Preserve arbitrary complete zero-block endpoint bits, not merely the normal frame's low-word sentinel.
            var registers = default(RegisterFile)
            for slot in 0..<13: registers[slot] = RegisterValue(0xfedcba9876540000'u64+uint64(slot))
            registers[0] = RegisterValue(initial)
            registers[1] = RegisterValue(5)
            var expectedRegisters = registers
            var state = [gas, quota, 0'u64, 0'u64, sentinel]
            var expected = state
            var destination = 7'u32
            while destination < 10:
              # A complete source block checks quota then gas before changing any guest/context byte.
              let index = int(destination-7)
              let price = uint64(3+index*2)
              if expected[1] < 2 or expected[0] < price: break
              expected[0] -= price
              expected[1] -= 2
              inc expected[index+2]
              expected[4] = uint64(destination)
              expectedRegisters[0] = RegisterValue(uint64(expectedRegisters[0])+1)
              if uint64(expectedRegisters[0]) >= 5:
                destination = 10
              else:
                destination = if active == 1 or index == 1: 7'u32 else: 8'u32
            let returned = callX86Region(jit, registers, state)
            assert returned == destination
            assert registers == expectedRegisters
            assert state == expected
            inc result

var contextCases = 0
var residentContextCases = 0
when not defined(pvmX86JitRefuse):
  let addSlots = instructionRegisters(instruction(branchProgram, CodeAddress(0)))
  let compareSlots = instructionRegisters(instruction(branchProgram, CodeAddress(3)))
  contextCases = checkRegionContext(addSlots, compareSlots, -1)
  for resident in 0..<13:
    # All thirteen guest coordinates include the modified counter, read-only branch bound and untouched lanes.
    residentContextCases += checkRegionContext(addSlots, compareSlots, resident)
stdout.writeLine("X86_RESIDENT_CONTEXT_CASES," & $contextCases)
stdout.writeLine("X86_RESIDENT_SLOT_CONTEXT_CASES," & $residentContextCases)


# Native-only full-bit literals cover every signed immediate encoding boundary and its mandatory fallback neighbors.
var compactCases = 0
when not defined(pvmX86JitRefuse):
  const literals = [0'u64, 1, 127, 128, 255, 0x7fffffff'u64, 0x80000000'u64,
    0xffffffff'u64, 0x100000000'u64, 0x7fffffffffffffff'u64, 0x8000000000000000'u64,
    0xffffffff7fffffff'u64, 0xffffffff80000000'u64, 0xffffffffffffff7f'u64,
    0xffffffffffffff80'u64, high(uint64)]
  const seeds = [0'u64, 1, 127, 128, 0x7fffffff'u64, 0x80000000'u64,
    0xffffffff'u64, 0x8000000000000000'u64, high(uint64)]
  for opcode in [132'u8, 133, 134, 149]:
    for alias in [0x10'u8, 0x00, 0xcc]:
      # Genuine decoded slots cover distinct sources, self aliases and the highest guest register.
      let source = owner([@[opcode, alias, 0], @[0'u8]])
      let slots = instructionRegisters(instruction(source, CodeAddress(0)))
      for value in literals:
        let jit = newX86Jit()
        discard x86Entry(jit, 0, 4)
        var fragment = default(X86Block)
        emitX86Operation(fragment, opcode, slots, value)
        for index in 0..<3: emitX86Operation(fragment, 100, identitySlots, 0)
        assert publishX86Entry(jit, 0, 4, 4, fragment)
        for seed in seeds:
          # Wrapping equations use the full original constants, independently of emitter width selection.
          var registers = default(RegisterFile)
          for index in 0..<13: registers[index] = RegisterValue(uint64(index)+100)
          registers[slots.bIndex] = RegisterValue(seed)
          var expected = registers
          let wanted = case opcode
            of 132: seed and value
            of 133: seed xor value
            of 134: seed or value
            else: seed+value
          expected[slots.destinationIndex] = RegisterValue(wanted)
          assert callX86Entry(jit, 0, registers) == 4
          assert registers == expected
          inc compactCases
  for opcode in 81'u8..90'u8:
    let source = owner([@[opcode, 0x10, 0, 0], @[0'u8]])
    let slots = instructionRegisters(instruction(source, CodeAddress(0)))
    for right in literals:
      let jit = newX86Jit()
      discard x86Entry(jit, 0, 8)
      var warm = default(X86Block)
      for index in 0..<4: emitX86Operation(warm, 100, identitySlots, 0)
      assert publishX86Entry(jit, 0, 4, 4, warm)
      var control = default(X86Block)
      for index in 0..<4: emitX86Operation(control, 100, identitySlots, 0)
      emitX86Branch(control, opcode, slots, right, 6, 7)
      assert publishX86Entry(jit, 0, 4, 5, control, conditional = true)
      for left in seeds:
        # XOR of the sign bit orders signed values without a narrowing cast or host signed-overflow dependency.
        let signedLeft = left xor 0x8000000000000000'u64
        let signedRight = right xor 0x8000000000000000'u64
        let taken = case opcode
          of 81: left == right
          of 82: left != right
          of 83: left < right
          of 84: left <= right
          of 85: left >= right
          of 86: left > right
          of 87: signedLeft < signedRight
          of 88: signedLeft <= signedRight
          of 89: signedLeft >= signedRight
          else: signedLeft > signedRight
        var registers = default(RegisterFile)
        for index in 0..<13: registers[index] = RegisterValue(uint64(index)+100)
        registers[slots.aIndex] = RegisterValue(left)
        let original = registers
        assert callX86Branch(jit, 0, registers) == (if taken: 6'u32 else: 7'u32)
        assert registers == original
        inc compactCases
stdout.writeLine("X86_COMPACT_IMMEDIATE_CASES," & $compactCases)


var residentArithmeticCases = 0
when not defined(pvmX86JitRefuse):
  for opcode in 0..255:
    if not supportedX86Opcode(byte(opcode)): continue
    for pattern in [0'u8, 17, 128, 255]:
      var part = @[byte(opcode)]
      for index in 0..<24: part.add(pattern)
      let source = owner([part, part, part, part, @[0'u8]])
      let decoded = instruction(source, CodeAddress(0))
      assert decoded.error == ProgramError.None
      let slots = instructionRegisters(decoded)
      for resident in 0..<13:
        # A genuine connected region provides/commits R11; an ordinary entry must refuse this builder shape.
        let jit = newX86Jit()
        discard x86Entry(jit, 0, 32)
        var invalid = newX86ResidentBlock(range[0..12](resident))
        emitX86Operation(invalid, 100, identitySlots, 0)
        assert not publishX86Entry(jit, 0, 4, 4, invalid)
        var warm = default(X86Block)
        for index in 0..<4: emitX86Operation(warm, 100, identitySlots, 0)
        assert publishX86Entry(jit, 0, 4, 4, warm)
        var body = newX86ResidentBlock(range[0..12](resident))
        for index in 0..<4: emitX86Operation(body, byte(opcode), slots, uint64(decoded.value.x))
        emitX86Branch(body, 81, slots, 0, 10, 10)
        var blocks = default(array[2, X86RegionBlock])
        blocks[0] = X86RegionBlock(header: 7, span: 5, operations: 5,
          price: 1, yes: 10, no: 10, body: move(body))
        assert publishX86Region(jit, blocks, 1)
        for seed in [0'u64, 31, 32, 63, 64, 127, 0x80000000'u64, 0xffffffff'u64,
            0x8000000000000000'u64, high(uint64)]:
          var registers = default(RegisterFile)
          for index in 0..<13: registers[index] = RegisterValue(seed xor uint64(index))
          var expected = registers
          for index in 0..<4:
            # The portable evaluator consumes owner-decoded operands; it cannot consult resident code or builder fields.
            let evaluated = evaluateRegisters(source, CodeAddress(uint32(index*25)), expected)
            assert evaluated.error == RegisterError.None
            expected = evaluated.value
          var context = [100'u64, 5'u64, 0'u64, 0'u64, 0xfedcba9876543210'u64]
          assert callX86Region(jit, registers, context) == 10
          assert registers == expected
          assert context == [99'u64, 0'u64, 1'u64, 0'u64, 7'u64]
          inc residentArithmeticCases
stdout.writeLine("X86_RESIDENT_SLOT_ARITHMETIC_CASES," & $residentArithmeticCases)


var residentRefusals = 0
when not defined(pvmX86JitRefuse):
  for mismatch in 0..<2:
    # A cold builder cannot mix resident coordinates or mix resident/ordinary bodies under one prologue.
    let jit = newX86Jit()
    discard x86Entry(jit, 0, 32)
    var warm = default(X86Block)
    for index in 0..<4: emitX86Operation(warm, 100, identitySlots, 0)
    assert publishX86Entry(jit, 0, 4, 4, warm)
    var blocks = default(array[2, X86RegionBlock])
    for index in 0..<2:
      var body = if index == 0: newX86ResidentBlock(0)
        elif mismatch == 0: newX86ResidentBlock(1) else: default(X86Block)
      emitX86Operation(body, 100, identitySlots, 0)
      emitX86Branch(body, 81, identitySlots, 0, 7, 10)
      blocks[index] = X86RegionBlock(header: uint32(7+index), span: 2, operations: 2,
        price: 1, yes: 7, no: 10, body: move(body))
    assert not publishX86Region(jit, blocks, 2)
    assert x86RegionStatus(jit) == 1
    inc residentRefusals
stdout.writeLine("X86_RESIDENT_SLOT_REFUSALS," & $residentRefusals)
