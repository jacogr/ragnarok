# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve the pinned unsigned gas domain while separating public PolkaVM's signed input boundary.
## Host debt witnesses deliberately retain GP 0.8.0 behavior pending coordinated PR533 adoption.

# @@Verification={"arc": "pvm_gas_domain_arc_release"}

import std/assertions
import std/syncio
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step
import ../../../src/pvm/host_gas as pvm_host_gas
import ../../support/testing_arc_evidence

proc unexpected(calls: var int, suspension: StepOutcome): HostResponse {.raises: [].} =
  ## A trap-only guest must never invoke the callback; callers assert the count remains zero.
  inc calls
  let cpu = machineInfo(suspension.machine).value
  HostResponse(action: HostAction.Panic, gas: cpu.gas, gasDeficit: cpu.gasDeficit,
    registers: cpu.registers, memory: memoryOf(suspension.machine).value)

proc cycle() =
  ## Compare the complete common-domain controls and native-only upper half without signed narrowing.
  let raw = [0'u8, 0, 1, 0, 1]
  let paper = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(5), JumpCountLimit(0)).value
  let jam = decodeJamProgram(raw, CodeAddress(0), ProgramByteLimit(5), JumpCountLimit(0)).value
  let memory = captureMemory(default(seq[PageImage]), PageLimit(0)).value
  var registers = default(RegisterFile)
  for i in 0..<13:
    # High-bit sentinels make narrowing or unintended mutations visible in every terminal result.
    registers[i] = RegisterValue(high(uint64) - uint64(i))
  for program in [paper, jam]:
    assert uint64(blockGas(program, CodeAddress(0), GasCycleLimit(5)).value) == 2
    for available in [0'u64, 1, 2, 47, 48, 49, 0x7ffffffffffffffe'u64, 0x7fffffffffffffff'u64,
        0x8000000000000000'u64, 0x8000000000000001'u64, high(uint64) - 1, high(uint64)]:
      # The last four values cannot be represented as positive gas through public PolkaVM's i64 API.
      let original = captureMachine(program, memory, MachineInfo(pc: CodeAddress(0),
        gas: MachineGas(available), gasDeficit: GasDeficit(0), blockCharged: false,
        registers: registers)).value
      var calls = 0
      let withHost = executeWithHost(original, calls, unexpected, ExecutionStepLimit(1),
        HostCallLimit(0), GasCycleLimit(5))
      let guest = execute(original, ExecutionStepLimit(1), GasCycleLimit(5))
      assert calls == 0
      for completed in [guest, withHost]:
        # Host-aware execution must preserve the full unsigned posterior even without a host dispatch.
        assert completed.error == StepError.None
        let outcome = completed.value
        let cpu = machineInfo(outcome.machine).value
        assert outcome.exit == (if available < 2: StepExit.OutOfGas else: StepExit.Panic)
        assert uint64(cpu.pc) == 0 and cpu.blockCharged == (available >= 2)
        assert uint64(cpu.gas) == (if available < 2: available else: available - 2)
        assert uint64(cpu.gasDeficit) == 0
        for r in 0..<13:
          # Complete copied CPU state, not just the exit kind, belongs to each boundary witness.
          assert uint64(cpu.registers[r]) == uint64(registers[r])
          assert uint64(machineInfo(original).value.registers[r]) == uint64(registers[r])
      assert uint64(machineInfo(original).value.gas) == available
      assert not machineInfo(original).value.blockCharged
  let charged = gasHostResponse(MachineGas(0), registers, memory)
  assert charged.action == HostAction.OutOfGas and uint64(charged.gas) == 0
  assert uint64(charged.gasDeficit) == 0
  for r in 0..<13:
    # Underfunded Omega_G preserves every register under the pinned pre-PR533 equation.
    assert uint64(charged.registers[r]) == uint64(registers[r])

cycle()
let before = getOccupiedMem()
for iteration in 0..<1000:
  # Private immutable roots from all unsigned edge cases are released without retaining execution history.
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_gas_domain_reference", 1000, before, after)
echo "PVM gas-domain boundary checks passed: 12 inputs, 2 profiles"
echo "ARC_RELEASE cycles=1000 unchanged"
