# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent GP jump-table width/count witnesses, including zero-width runtime behavior.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, gas, step]

for width in 0..255:
  for count in 0..1:
    # Literal host0 at PC0, jump_ind r8 at PC2; E_z zero entries require no encoder.
    var wire = @[byte(count), byte(width), 4'u8]
    for index in 0..<(count * width): wire.add(0)
    for octet in [10'u8, 0, 50, 8, 5]: wire.add(octet)
    let parsed = decodeProgram(wire, CodeAddress(2), ProgramByteLimit(512), JumpCountLimit(1))
    assert parsed.error == ProgramError.None
    if count == 1:
      assert uint64(jumpTarget(parsed.value, JumpIndex(0)).value) == 0
    else:
      assert jumpTarget(parsed.value, JumpIndex(0)).error == ProgramError.InvalidIndex
    var registers = default(RegisterFile)
    registers[8] = RegisterValue(2)
    let source = captureMachine(parsed.value, captureMemory([], PageLimit(0)).value,
      MachineInfo(pc: CodeAddress(2), gas: MachineGas(1000), blockCharged: true,
        registers: registers)).value
    let first = stepOnce(source, GasCycleLimit(1000))
    assert first.error == StepError.None
    assert first.value.exit == (if count == 1: StepExit.Continued else: StepExit.Panic)
    assert uint64(machineInfo(first.value.machine).value.pc) == (if count == 1: 0'u64 else: 2'u64)
    let completed = execute(source, ExecutionStepLimit(2), GasCycleLimit(1000))
    assert completed.error == StepError.None
    assert completed.value.exit == (if count == 1: StepExit.Host else: StepExit.Panic)
    if count == 1:
      assert uint64(completed.value.hostCall) == 0
    for index in 0..<13:
      # Neither the dynamic jump nor host suspension writes a register, including the original source.
      assert uint64(machineInfo(completed.value.machine).value.registers[index]) == uint64(
          registers[index])
      assert uint64(machineInfo(source).value.registers[index]) == uint64(registers[index])
    assert uint64(machineInfo(source).value.pc) == 2
    assert uint64(machineInfo(source).value.gas) == 1000 and machineInfo(source).value.blockCharged

echo "PVM paper jump-table witnesses passed: 512; GP-PVM-005/006 recorded"
