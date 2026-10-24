# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native tests replay charged execution traces and check out-of-gas ordering and ARC lifetimes.
## The executable reads RAGNAROK_PVM_STEP, tests all stepping entry points and records pvm_step ARC evidence.

# @@Verification={"arc": "pvm_step_arc_release"}

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, registers, gas, gas_plan, step]
import ../../support/arc_evidence

# Read independently serialized little-endian fixture integers after checking their enclosing extent.
proc word(data: string, at, width: int): uint64 =
  result = 0
  # No production decoder participates in reading expected CPU values.
  for i in 0..<width: result = result or (uint64(byte(data[at + i])) shl (8 * i))

# Compare all CPU fields explicitly; nominal values are compared only within their own domains.
proc same(actual, expected: MachineInfo) =
  assert uint64(actual.pc) == uint64(expected.pc)
  assert uint64(actual.gas) == uint64(expected.gas)
  assert actual.blockCharged == expected.blockCharged
  # A step must preserve every unrelated register, not merely the instruction destination.
  for i in 0..<13: assert uint64(actual.registers[i]) == uint64(expected.registers[i])

# Supply readable sentinel memory so every stepped snapshot can prove memory preservation.
proc memoryOwner(): Memory =
  var page = PageImage(index: PageIndex(16), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  page.bytes[0] = 165
  let captured = captureMemory([page], PageLimit(1))
  assert captured.error == MachineError.None
  captured.value

# Capture an independently serialized short program for API boundary and ownership tests.
proc smallProgram(code: openArray[byte], mask: byte): Program =
  assert code.len < 8
  var bytes = @[0'u8, 0, byte(code.len)]
  # Caller supplies explicit opcode bits, including unmarked bytes equal to termination opcodes.
  for value in code: bytes.add(value)
  bytes.add(mask)
  let captured = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0))
  assert captured.error == ProgramError.None
  captured.value

var data = ""
# Missing evidence is a failing setup, not an implicitly skipped execution corpus.
try:
  data = readFile(getEnv("RAGNAROK_PVM_STEP"))
except:
  # I/O failures must propagate as a nonzero native test status.
  quit 2
assert data.len >= 12 and data[0..7] == "PVMSTEP1"
let count = int(word(data, 8, 4))
assert count == 186
var cursor = 12
var seen = default(array[256, bool])
let memory = memoryOwner()
# Replay each trace at exact gas, surplus gas and zero prepaid gas.
for row in 0..<count:
  assert data.len - cursor >= 132
  let length = int(word(data, cursor, 4))
  let entry = word(data, cursor + 4, 4)
  let price = word(data, cursor + 8, 8)
  let cycles = word(data, cursor + 16, 8)
  var initial = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(price), blockCharged: false,
    registers: default(RegisterFile))
  # Copy all initial registers from the independently generated trace.
  for i in 0..<13: initial.registers[i] = RegisterValue(word(data, cursor + 24 + i * 8, 8))
  let steps = int(word(data, cursor + 128, 4))
  cursor += 132
  assert length <= data.len - cursor
  var bytes = newSeq[byte](length)
  # The native program decoder receives the frozen encoding, not a synthesized production output.
  for i in 0..<length: bytes[i] = byte(data[cursor + i])
  cursor += length
  assert steps > 0 and steps <= (data.len - cursor) div 108
  let owner = decodeProgram(bytes, CodeAddress(entry), ProgramByteLimit(uint64(length)),
    JumpCountLimit(0))
  assert owner.error == ProgramError.None
  assert price > 0
  var insufficient = initial
  insufficient.gas = MachineGas(price - 1)
  let source = captureMachine(owner.value, memory, insufficient).value
  let exhausted = stepRegisters(source, GasCycleLimit(cycles))
  assert exhausted.error == StepError.None and exhausted.value.exit == StepExit.OutOfGas
  same(machineInfo(exhausted.value.machine).value, insufficient)
  same(machineInfo(source).value, insufficient)
  assert uint64(load(memoryOf(exhausted.value.machine).value, MemoryAddress(65536),
    AccessWidth(1)).value) == 165
  # Guest gas cannot substitute for the independent local simulation work budget.
  let limited = captureMachine(owner.value, memory, initial).value
  assert stepRegisters(limited, GasCycleLimit(cycles - 1)).error == StepError.GasCycleLimitExceeded
  same(machineInfo(limited).value, initial)
  for mode in 0..<3:
    # Prepaid blocks bypass both cost simulation and subtraction, even with no remaining gas.
    var expected = initial
    expected.gas = MachineGas(if mode == 0: price elif mode == 1: price + 17 else: 0)
    expected.blockCharged = mode == 2
    var current = captureMachine(owner.value, memory, expected).value
    for index in 0..<steps:
      # Each instruction must advance by its own decoded skip and preserve the prior snapshot.
      let prior = current
      let priorInfo = machineInfo(prior).value
      let decoded = instruction(programOf(prior).value, priorInfo.pc).value
      seen[int(decoded.opcode)] = true
      let advanced = stepRegisters(current, GasCycleLimit(if index == 0 and mode !=
          2: cycles else: 0))
      assert advanced.error == StepError.None and advanced.value.exit == StepExit.Continued
      current = advanced.value.machine
      expected.pc = CodeAddress(word(data, cursor + index * 108, 4))
      expected.gas = MachineGas(if mode == 1: 17 else: 0)
      expected.blockCharged = true
      # Expected register arrays come from the independent mathematical oracle.
      for i in 0..<13:
        expected.registers[i] = RegisterValue(word(data, cursor + index * 108 + 4 + i * 8, 8))
      same(machineInfo(current).value, expected)
      # The broader entry point must match independent arithmetic traces without changing legacy scope.
      let broad = stepControl(prior, GasCycleLimit(if index == 0 and mode != 2: cycles else: 0))
      assert broad.error == StepError.None and broad.value.exit == StepExit.Continued
      same(machineInfo(broad.value.machine).value, expected)
      # Memory-capable stepping must preserve the same independent register-only expectations.
      let memoryCapable = stepMemory(prior, GasCycleLimit(if index == 0 and mode !=
          2: cycles else: 0))
      assert memoryCapable.error == StepError.None and memoryCapable.value.exit ==
          StepExit.Continued
      same(machineInfo(memoryCapable.value.machine).value, expected)
      # Complete Psi_1 capability preserves the same independent arithmetic trace expectations.
      let full = stepOnce(prior, GasCycleLimit(if index == 0 and mode != 2: cycles else: 0))
      assert full.error == StepError.None and full.value.exit == StepExit.Continued
      same(machineInfo(full.value.machine).value, expected)
      same(machineInfo(prior).value, priorInfo)
      assert uint64(load(memoryOf(current).value, MemoryAddress(65536), AccessWidth(1)).value) == 165
    # Trap is deliberately outside this bounded executor, never a fabricated terminal outcome.
    assert stepRegisters(current, GasCycleLimit(0)).error == StepError.UnsupportedInstruction
  cursor += steps * 108
assert cursor == data.len
var covered = 0
# Coverage is measured from executed instructions, including all saturated/aliased encodings.
for op in 0..<256:
  if seen[op]: inc covered
assert covered == 85
let uninitialized = default(StepResult)
assert uninitialized.error == StepError.Uninitialized
assert stepRegisters(default(Machine), GasCycleLimit(100)).error == StepError.InvalidMachine
assert programOf(default(Machine)).error == MachineError.InvalidOwner

# Every unsupported valid opcode must stay a local error, irrespective of gas or charged state.
for op in 0..255:
  if validOpcode(byte(op)) and not registerOnlyOpcode(byte(op)):
    let owner = smallProgram([byte(op), 0], 3)
    for prepaid in [false, true]:
      # Even zero gas cannot turn an unsupported operation into a claimed guest evaluation.
      let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(0), blockCharged: prepaid,
        registers: default(RegisterFile))
      let source = captureMachine(owner, memory, info).value
      assert stepRegisters(source, GasCycleLimit(0)).error == StepError.UnsupportedInstruction
      if not terminatesBlock(byte(op)) and op != 2:
        # Memory and host operations remain unsupported by the broader entry point too.
        assert stepControl(source, GasCycleLimit(0)).error == StepError.UnsupportedInstruction
      same(machineInfo(source).value, info)

# All valid opcode families retain their public capability boundary before affordability; the literal dispatch table must not add or omit a permission.
for opcode in 0..255:
  if not validOpcode(byte(opcode)): continue # Reserved bytes have no captured instruction to classify.
  let owner = smallProgram([byte(opcode), 0], 3)
  let prepared = newGasPlan(owner, GasPlanLimits(blocks: GasPlanBlockLimit(2),
    bytes: GasPlanByteLimit(16), cycles: GasCycleLimit(10000)))
  assert prepared.error == GasPlanError.None
  let plan = prepared.value
  let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(0), blockCharged: false,
    registers: default(RegisterFile))
  let source = captureMachine(owner, memory, info).value
  for planned in [false, true]:
    for scope in 0..<4:
      # The public capability hierarchy follows the instruction families, independently of the production classification bytes.
      let allowed = registerOnlyOpcode(byte(opcode)) or
        (scope >= 1 and (terminatesBlock(byte(opcode)) or opcode == 2)) or
        (scope >= 2 and (opcode in 30..33 or opcode in 52..62 or opcode in 70..73 or opcode in
            120..130)) or
        (scope == 3 and opcode == 10)
      var answer = default(StepResult)
      template advance(policy: untyped) =
        # Exercise each real public overload; no private classification accessor supplies the expected result.
        case scope
        of 0: answer = stepRegisters(source, policy)
        of 1: answer = stepControl(source, policy)
        of 2: answer = stepMemory(source, policy)
        else: answer = stepOnce(source, policy)
      if planned: advance(plan) # A matching complete plan does not authorize a broader evaluator scope.
      else: advance(GasCycleLimit(10000)) # Dynamic pricing must preserve the same rejection-before-debit ordering.
      if allowed:
        assert answer.error == StepError.None and answer.value.exit == StepExit.OutOfGas
        same(machineInfo(answer.value.machine).value, info)
      else:
        assert answer.error == StepError.UnsupportedInstruction
      same(machineInfo(source).value, info)

# Whole-block scanning prices a later wrapped negative target before committing the first register mutation.
let scanned = smallProgram([51'u8, 0, 7, 170, 0, 252], 9)
var scannedRegisters = default(RegisterFile)
scannedRegisters[0] = RegisterValue(99)
let scannedInfo = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), blockCharged: false,
  registers: scannedRegisters)
let scannedMachine = captureMachine(scanned, memory, scannedInfo).value
let scannedPrice = blockGas(scanned, CodeAddress(0), GasCycleLimit(5))
assert scannedPrice.error == GasError.None and uint64(scannedPrice.value) == 2
assert blockGas(scanned, CodeAddress(0), GasCycleLimit(4)).error == GasError.CycleLimitExceeded
let scannedStep = stepRegisters(scannedMachine, GasCycleLimit(1000))
assert scannedStep.error == StepError.None and scannedStep.value.exit == StepExit.Continued
var scannedExpected = scannedInfo
scannedExpected.pc = CodeAddress(3)
scannedExpected.registers[0] = RegisterValue(7)
scannedExpected.gas = MachineGas(1000 - uint64(scannedPrice.value))
scannedExpected.blockCharged = true
same(machineInfo(scannedStep.value.machine).value, scannedExpected)
same(machineInfo(scannedMachine).value, scannedInfo)
# A trusted prepaid snapshot still bypasses pricing and preserves zero gas while performing the same mutation.
var prepaidInfo = scannedInfo
prepaidInfo.blockCharged = true
prepaidInfo.gas = MachineGas(0)
let prepaid = captureMachine(scanned, memory, prepaidInfo).value
let resumed = stepRegisters(prepaid, GasCycleLimit(0))
assert resumed.error == StepError.None and resumed.value.exit == StepExit.Continued
assert uint64(machineInfo(resumed.value.machine).value.pc) == 3
assert uint64(machineInfo(resumed.value.machine).value.registers[0]) == 7
assert uint64(machineInfo(resumed.value.machine).value.gas) == 0

# Boundary lookup must ignore terminator-valued operand bytes and reject unmarked/out-of-range PCs.
let boundaries = smallProgram([0'u8, 51, 0, 100, 0, 0], 43)
assert uint64(containingBlockStart(boundaries, CodeAddress(3)).value) == 1
assert containingBlockStart(boundaries, CodeAddress(2)).error == ProgramError.InvalidInstruction
assert containingBlockStart(boundaries, CodeAddress(high(uint64))).error ==
    ProgramError.InvalidInstruction
assert containingBlockStart(default(Program), CodeAddress(0)).error == ProgramError.InvalidOwner

# Construct small independent bytecode witnesses with explicit instruction boundaries and table entries.
proc controlProgram(parts: openArray[seq[byte]], jumps: openArray[uint32]): Program =
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  # Boundaries come from the test's instruction partition, never the production decoder.
  for part in parts:
    starts.add(code.len)
    # Append bytes explicitly on the pinned Nimony sequence API.
    for value in part: code.add(value)
  assert code.len < 128 and jumps.len < 128
  var bytes = @[byte(jumps.len), 4'u8, byte(code.len)]
  # Encode fixed-width jump-table entries directly in little endian.
  for target in jumps:
    # Every table entry has the declared four-byte width.
    for shift in 0..<4: bytes.add(byte((target shr (shift * 8)) and 255))
  # Copy the instruction stream before its bitmap.
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len + 7) div 8)
  # Explicit starts also permit trap-valued bytes inside operands.
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  # Append the exact packed bitmap.
  for value in mask: bytes.add(value)
  let decoded = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(1024), JumpCountLimit(128))
  assert decoded.error == ProgramError.None
  decoded.value

# Check every control witness at prepaid zero gas and charged/insufficient gas.
# Expected register/PC values are supplied independently by each test, not derived from execution.
proc controlCase(owner: Program, entry: uint64, registers: RegisterFile,
    expectedExit: StepExit, expectedPc: uint64, expectedRegisters: RegisterFile,
    continuedCharged = false) =
  let start = containingBlockStart(owner, CodeAddress(entry)).value
  let price = blockGas(owner, start, GasCycleLimit(1000))
  assert price.error == GasError.None
  # The PolkaVM adoption gives negative targets a defined price before the independent jump-validity check.
  for prepaid in [true, false]:
    let initial = MachineInfo(pc: CodeAddress(entry), gas: MachineGas(
        if prepaid: 0'u64 else: 10000'u64),
      blockCharged: prepaid, registers: registers)
    let source = captureMachine(owner, memory, initial).value
    let answer = stepControl(source, GasCycleLimit(if prepaid: 0'u64 else: 1000'u64))
    assert answer.error == StepError.None
    assert answer.value.exit == expectedExit
    var expected = initial
    expected.pc = CodeAddress(expectedPc)
    expected.registers = expectedRegisters
    expected.blockCharged = expectedExit != StepExit.Continued or continuedCharged
    if not prepaid:
      # The existing independent gas suite owns exact pipeline pricing; this checks composition.
      expected.gas = MachineGas(10000 - uint64(price.value))
    same(machineInfo(answer.value.machine).value, expected)
    # The broader memory capability preserves every existing control-flow outcome and snapshot.
    let memoryCapable = stepMemory(source, GasCycleLimit(if prepaid: 0'u64 else: 1000'u64))
    assert memoryCapable.error == StepError.None and memoryCapable.value.exit == expectedExit
    same(machineInfo(memoryCapable.value.machine).value, expected)
    # Adding ecalli support must preserve every already-covered control mutation and terminal PC.
    let full = stepOnce(source, GasCycleLimit(if prepaid: 0'u64 else: 1000'u64))
    assert full.error == StepError.None and full.value.exit == expectedExit
    same(machineInfo(full.value.machine).value, expected)
    same(machineInfo(source).value, initial)
    assert uint64(load(memoryOf(answer.value.machine).value, MemoryAddress(65536),
        AccessWidth(1)).value) == 165
    if not prepaid and uint64(price.value) > 0:
      # Gas insufficiency outranks panic/halt/register mutation and leaves the original snapshot intact.
      var low = initial
      low.gas = MachineGas(uint64(price.value) - 1)
      let insufficient = captureMachine(owner, memory, low).value
      let stopped = stepControl(insufficient, GasCycleLimit(1000)).value
      assert stopped.exit == StepExit.OutOfGas
      same(machineInfo(stopped.machine).value, low)

let zeroRegisters = default(RegisterFile)
# Trap uses the default increment, including beyond code; fallthrough cannot enter the zero suffix.
controlCase(controlProgram([@[1'u8], @[0'u8, 99, 88]], []), 1, zeroRegisters,
  StepExit.Panic, 4, zeroRegisters)
controlCase(controlProgram([@[1'u8]], []), 0, zeroRegisters, StepExit.Panic, 0, zeroRegisters)
controlCase(controlProgram([@[1'u8], @[0'u8]], []), 0, zeroRegisters,
  StepExit.Continued, 1, zeroRegisters)
controlCase(controlProgram([@[2'u8], @[0'u8]], []), 0, zeroRegisters,
  StepExit.Continued, 1, zeroRegisters, true)
# Static jumps cover forward, self, backward, operand, outside-code and mathematical-negative targets.
controlCase(controlProgram([@[40'u8, 2], @[0'u8]], []), 0, zeroRegisters,
  StepExit.Continued, 2, zeroRegisters)
controlCase(controlProgram([@[40'u8, 0]], []), 0, zeroRegisters,
  StepExit.Continued, 0, zeroRegisters)
controlCase(controlProgram([@[1'u8], @[40'u8, 255]], []), 1, zeroRegisters,
  StepExit.Continued, 0, zeroRegisters)
# Invalid targets never silently wrap into the bytecode or accept operand bytes.
for offset in [1'u8, 20'u8, 255'u8]:
  controlCase(controlProgram([@[40'u8, offset], @[0'u8]], []), 0, zeroRegisters,
    StepExit.Panic, 0, zeroRegisters)

# Independent signed/unsigned ordering witnesses include equality, sign boundaries and extreme values.
let values = [0'u64, 1'u64, 0x7fffffffffffffff'u64, 0x8000000000000000'u64, high(uint64)]
# Literal ranks specify signed order independently of the implementation's bit-flip comparison.
let signedRanks = [2, 3, 4, 0, 1]
for left in 0..<values.len:
  # Cross each left boundary with every independently ranked right boundary.
  for right in 0..<values.len:
    var regs = zeroRegisters
    regs[0] = RegisterValue(values[left])
    regs[1] = RegisterValue(values[right])
    let conditions = [left == right, left != right, left < right,
      signedRanks[left] < signedRanks[right], left >= right, signedRanks[left] >= signedRanks[right]]
    # Every register branch is checked taken and untaken, including equal and signed-extreme operands.
    for op in 170..175:
      let owner = controlProgram([@[byte(op), 16'u8, 4], @[0'u8], @[0'u8]], [])
      controlCase(owner, 0, regs, StepExit.Continued,
        (if conditions[op - 170]: 4'u64 else: 3'u64), regs)

# Immediate branch comparisons use literal sign-extended byte values and their independent signed ranks.
let immValues = [0'u64, 1'u64, high(uint64)]
let immRanks = [2, 3, 1]
for left in 0..<values.len:
  # Cross each left boundary with every independently ranked right boundary.
  for right in 0..<immValues.len:
    var regs = zeroRegisters
    regs[0] = RegisterValue(values[left])
    let a = values[left]
    let b = immValues[right]
    let conditions = [a == b, a != b, a < b, a <= b, a >= b, a > b,
      signedRanks[left] < immRanks[right], signedRanks[left] <= immRanks[right],
      signedRanks[left] >= immRanks[right], signedRanks[left] > immRanks[right]]
    # Exercise every immediate comparison with the same independent truth table.
    for op in 81..90:
      # X is one byte; Y targets the second of two independent trap blocks.
      let owner = controlProgram([@[byte(op), 16'u8, byte(b and 255), 5], @[0'u8], @[0'u8]], [])
      controlCase(owner, 0, regs, StepExit.Continued,
        (if conditions[op - 81]: 5'u64 else: 4'u64), regs)

# Both branch destinations are checked regardless of condition; the final branch has no fallthrough.
for op in 81..90:
  controlCase(controlProgram([@[byte(op), 16'u8, 1, 1], @[0'u8]], []), 0,
    zeroRegisters, StepExit.Panic, 0, zeroRegisters)
  controlCase(controlProgram([@[byte(op), 16'u8, 1, 0]], []), 0,
    zeroRegisters, StepExit.Panic, 0, zeroRegisters)
for op in 170..175:
  controlCase(controlProgram([@[byte(op), 16'u8, 1], @[0'u8]], []), 0,
    zeroRegisters, StepExit.Panic, 0, zeroRegisters)
  controlCase(controlProgram([@[byte(op), 16'u8, 0]], []), 0,
    zeroRegisters, StepExit.Panic, 0, zeroRegisters)

# Negative conditional targets now panic consistently under prepaid and freshly charged execution.
controlCase(controlProgram([@[81'u8, 16, 1, 255], @[0'u8]], []), 0,
  zeroRegisters, StepExit.Panic, 0, zeroRegisters)
controlCase(controlProgram([@[170'u8, 16, 255], @[0'u8]], []), 0,
  zeroRegisters, StepExit.Panic, 0, zeroRegisters)
# A marked instruction inside a block is still an invalid static or dynamic destination.
controlCase(controlProgram([@[2'u8], @[40'u8, 0], @[0'u8]], []), 1,
  zeroRegisters, StepExit.Panic, 1, zeroRegisters)
var interiorRegs = zeroRegisters
interiorRegs[0] = RegisterValue(2)
controlCase(controlProgram([@[2'u8], @[50'u8, 0], @[0'u8]], [1'u32]), 1,
  interiorRegs, StepExit.Panic, 1, interiorRegs)
# Saturated register nibbles and independent destination/source registers remain decoder-defined.
var saturated = zeroRegisters
saturated[12] = RegisterValue(2)
controlCase(controlProgram([@[50'u8, 15], @[0'u8]], [2'u32]), 0,
  saturated, StepExit.Continued, 2, saturated)
var separate = zeroRegisters
separate[12] = RegisterValue(2)
var separateLoaded = separate
separateLoaded[0] = RegisterValue(high(uint64))
controlCase(controlProgram([@[180'u8, 240, 1, 255, 0], @[0'u8]], [5'u32]), 0,
  separate, StepExit.Continued, 5, separateLoaded)
# Dynamic jump addresses cover sentinel precedence, alignment, bounds, invalid targets and 32-bit wrap.
for address in [0'u64, 1'u64, 2'u64, 4'u64, 6'u64, 8'u64, 0xffff0000'u64, 0x100000002'u64]:
  var regs = zeroRegisters
  regs[0] = RegisterValue(address)
  let owner = controlProgram([@[50'u8, 0], @[0'u8]], [2'u32, 1'u32, 99'u32])
  let exit = (if address == 0xffff0000'u64: StepExit.Halt
    elif address == 2 or address == 0x100000002'u64: StepExit.Continued else: StepExit.Panic)
  controlCase(owner, 0, regs, exit, (if exit == StepExit.Continued: 2'u64 else: 0'u64), regs)
# Sign-extended -1 wraps a low zero to an unaligned invalid address, and turns three into table address two.
for address in [0'u64, 3'u64, high(uint64)]:
  var regs = zeroRegisters
  regs[0] = RegisterValue(address)
  controlCase(controlProgram([@[50'u8, 0, 255], @[0'u8]], [3'u32]), 0, regs,
    (if address == 3: StepExit.Continued else: StepExit.Panic),
    (if address == 3: 3'u64 else: 0'u64), regs)
# Load-and-jump writes even on panic and halt; aliased dynamic operands must use the old register value.
var loaded = zeroRegisters
loaded[0] = RegisterValue(7)
for offset in [0'u8, 1'u8, 4'u8]:
  controlCase(controlProgram([@[80'u8, 16, 7, offset], @[0'u8]], []), 0, zeroRegisters,
    (if offset == 1: StepExit.Panic else: StepExit.Continued), uint64(if offset ==
        1: 0'u8 else: offset), loaded)
controlCase(controlProgram([@[80'u8, 16, 7, 255], @[0'u8]], []), 0,
  zeroRegisters, StepExit.Panic, 0, loaded)
# Run the aliased dynamic form across failure, success and the halt sentinel.
for address in [0'u64, 2'u64, 0xffff0000'u64]:
  var regs = zeroRegisters
  regs[0] = RegisterValue(address)
  controlCase(controlProgram([@[180'u8, 0, 1, 7, 0], @[0'u8]], [5'u32]), 0, regs,
    (if address == 0: StepExit.Panic elif address == 2: StepExit.Continued else: StepExit.Halt),
    (if address == 2: 5'u64 else: 0'u64), loaded)

# A self-loop must clear the prepaid flag, then charge again until gas is insufficient.
let loopOwner = controlProgram([@[40'u8, 0]], [])
let loopCost = uint64(blockGas(loopOwner, CodeAddress(0), GasCycleLimit(1000)).value)
assert loopCost > 0
var looping = captureMachine(loopOwner, memory, MachineInfo(pc: CodeAddress(0),
  gas: MachineGas(loopCost * 2), blockCharged: false, registers: zeroRegisters)).value
for iteration in 0..<2:
  let next = stepControl(looping, GasCycleLimit(1000)).value
  assert next.exit == StepExit.Continued
  assert not machineInfo(next.machine).value.blockCharged
  looping = next.machine
let exhausted = stepControl(looping, GasCycleLimit(1000)).value
assert exhausted.exit == StepExit.OutOfGas
same(machineInfo(exhausted.machine).value, machineInfo(looping).value)
# Gas simulation limits stay local failures before a control mutation or charge is published.
let limited = captureMachine(loopOwner, memory, MachineInfo(pc: CodeAddress(0),
  gas: MachineGas(100), blockCharged: false, registers: zeroRegisters)).value
assert stepControl(limited, GasCycleLimit(0)).error == StepError.GasCycleLimitExceeded
assert stepControl(default(Machine), GasCycleLimit(0)).error == StepError.InvalidMachine
# Terminal capture accepts a non-executable PC but rejects absent owners; stepping it is a local failure.
let terminalInfo = MachineInfo(pc: CodeAddress(high(uint64)), gas: MachineGas(0),
  blockCharged: true, registers: zeroRegisters)
assert captureTerminalMachine(default(Program), memory, terminalInfo).error ==
    MachineError.InvalidProgram
assert captureTerminalMachine(loopOwner, default(Memory), terminalInfo).error ==
    MachineError.InvalidOwner
let terminal = captureTerminalMachine(loopOwner, memory, terminalInfo).value
assert stepControl(terminal, GasCycleLimit(0)).error == StepError.InvalidMachine

# Release a complete program/memory/source/step graph after proving copied child-state isolation.
proc releaseCycle() =
  let owner = smallProgram([51'u8, 0, 100, 0, 0], 21)
  let memory = memoryOwner()
  let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(high(uint64)), blockCharged: false,
    registers: default(RegisterFile))
  let source = captureMachine(owner, memory, info).value
  let first = stepRegisters(source, GasCycleLimit(100)).value.machine
  let second = stepRegisters(first, GasCycleLimit(0)).value.machine
  let changed = withRegister(second, RegisterIndex(0), RegisterValue(99)).value
  assert uint64(machineInfo(changed).value.registers[0]) == 99
  assert uint64(machineInfo(second).value.registers[0]) == 0
  assert uint64(machineInfo(source).value.gas) == high(uint64)
  assert uint64(machineInfo(first).value.gas) == high(uint64) - 2
  let stopped = stepControl(second, GasCycleLimit(0)).value
  assert stopped.exit == StepExit.Panic
  assert uint64(machineInfo(stopped.machine).value.pc) == 5

releaseCycle()
let before = getOccupiedMem()
# Repeated complete owner lifetimes detect retained cycles and accidental result/source back-references.
for iteration in 0..<1000: releaseCycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_step", 1000, before, after)
echo "PVM register and control stepping passed"
echo "ARC_RELEASE cycles=1000 unchanged"
