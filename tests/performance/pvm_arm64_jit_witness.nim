# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Local JIT alias/overflow and reservation witness against the engine's bounded single-step adapter.
import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, gas, step]
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


var nativeOperations = 0'u64
var cases = 0
for pattern in [0'u8, 17, 128, 255]:
  var parts: seq[seq[byte]] = @[]
  for index in 0..<36:
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
        for budget in [0'u64, 1, 2, 7, 35, 36, 37, 38, 100]:
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
let transferProgram = owner([@[200'u8, 0, 0], @[201'u8, 0, 0], @[0'u8]])
let transferPlan = newFlatPlan(transferProgram, GasCycleLimit(100000))
let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(1000), registers: default(RegisterFile))
var first = newFlatFrame(transferPlan, [], initial)
runFlat(first, 100)
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
  assert transferred[0] == 0 and transferred[1] == 0
  let retired = flatArmStatistics(first)
  echo "RETIRED_STATS,", retired[0], ",", retired[1]
  assert retired[0] == 0 and retired[1] == 0
# A final arithmetic opcode lacking genuine fallthrough is refused at source admission, before JIT authority exists.
let truncatedProgram = captureOwner([@[200'u8, 0, 0], @[201'u8, 0, 0]])
echo "TRUNCATED_ADMISSION,", truncatedProgram.error
assert truncatedProgram.error == ProgramError.InvalidProgram
