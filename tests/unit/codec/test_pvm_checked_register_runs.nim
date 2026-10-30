# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Compare a checked multi-register span with the default prepared policy at every attempt boundary.
## Literal final arithmetic and reordered entries prevent a shared transition from hiding a run error.
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/handler_stream

proc sameCpu(left, right: MachineInfo) =
  ## Check every copied CPU field after a completed or locally refused attempt.
  assert left.pc == right.pc and left.gas == right.gas
  assert left.gasDeficit == right.gasDeficit and left.blockCharged == right.blockCharged
  for index in 0..<13:
    # Aliased destination reads must observe the preceding operation in the run.
    assert left.registers[index] == right.registers[index]

let raw = @[
  0'u8, 0, 19,     # Zero jumps, one-byte jump width and 19 bytes of marked code.
  149, 0x77, 1,    # r7 = r7 + 1.
  133, 0x77, 1,    # r7 = r7 xor 1.
  132, 0x77, 1,    # r7 = r7 and 1.
  134, 0x77, 1,    # r7 = r7 or 1.
  149, 0x77, 1,    # r7 = r7 + 1.
  133, 0x77, 1,    # r7 = r7 xor 1.
  0,               # Trap terminates the block after all six register writes.
  0x49, 0x92, 0x04 # Genuine opcode starts at byte 0, 3, 6, 9, 12, 15 and 18.
]
let decoded = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(uint64(raw.len)),
    JumpCountLimit(0))
assert decoded.error == ProgramError.None
let source = decoded.value
let cycles = GasCycleLimit(100000)
let defaultPolicy = newFlatPlan(source, cycles)
var admitted = prepareFlatPlan(source, cycles, defaultFlatLimits(), allowNative = false)
assert admitted.error == FlatError.None
let interpreted = takeValue(admitted)

for pc in [0'u64, 9'u64, 3'u64, 15'u64, 0'u64]:
  for paid in [false, true]:
    for gas in [0'u64, 1000'u64]:
      var registers = default(RegisterFile)
      registers[7] = RegisterValue(10)
      let initial = MachineInfo(pc: CodeAddress(pc), gas: MachineGas(gas),
          blockCharged: paid, registers: registers)
      var plain = newFlatFrame(defaultPolicy, [], initial)
      var batched = newFlatFrame(interpreted, [], initial)
      for budget in [0'u64, 1, 2, 3, 4, 5, 6, 7, 1, 7]:
        # Reordered and repeated budgets exercise the temporary barrier and retained source cache.
        resetFlatFrame(plain, initial)
        resetFlatFrame(batched, initial)
        runFlat(plain, budget)
        runFlat(batched, budget)
        assert batched.reason == plain.reason and batched.exit == plain.exit
        sameCpu(batched.info, plain.info)
        assert flatNodes(batched) == flatNodes(plain)
        if pc == 0 and paid and gas == 1000 and budget == 7:
          # The six distinct arithmetic writes end with 3; trap publishes normalized PC zero.
          assert batched.exit == StepExit.Panic and uint64(batched.info.pc) == 0
          assert uint64(batched.info.registers[7]) == 3
        checkFlatSource(batched)

echo "PASS checked register runs / every budget / paid gas / reordered entries / immutable source"
