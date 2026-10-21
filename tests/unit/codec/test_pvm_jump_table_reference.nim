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
    assert parsed.error == (if width > 4: ProgramError.InvalidProgram else: ProgramError.None)
    if width > 4:
      continue # Current deblob rejects oversized widths before any executable owner can exist.
    if count == 1:
      assert uint64(jumpTarget(parsed.value, JumpIndex(0)).value) == 0
    else:
      assert jumpTarget(parsed.value, JumpIndex(0)).error == ProgramError.InvalidIndex
    let jam = decodeJamProgram(wire, CodeAddress(2), ProgramByteLimit(512), JumpCountLimit(1))
    assert jam.error == (if width > 4: ProgramError.InvalidProgram else: ProgramError.None)
    if width <= 4:
      let entry = jumpTarget(jam.value, JumpIndex(0))
      if count == 1 and width != 0:
        assert entry.error == ProgramError.None and uint64(entry.value) == 0
      else:
        assert entry.error == ProgramError.InvalidIndex
    # The declared count still consumes local policy even if the JAM profile hides width-zero entries.
    if count == 1:
      let limited = decodeJamProgram(wire, CodeAddress(2), ProgramByteLimit(512), JumpCountLimit(0))
      assert limited.error == ProgramError.LimitExceeded
    var registers = default(RegisterFile)
    registers[8] = RegisterValue(2)
    let source = captureMachine(parsed.value, captureMemory([], PageLimit(0)).value,
      MachineInfo(pc: CodeAddress(2), gas: MachineGas(1000), blockCharged: true,
        registers: registers)).value
    if width <= 4:
      let compatible = captureMachine(jam.value, captureMemory([], PageLimit(0)).value,
        machineInfo(source).value).value
      let observed = execute(compatible, ExecutionStepLimit(2), GasCycleLimit(1000))
      assert observed.error == StepError.None
      assert observed.value.exit == (if count == 1 and width !=
          0: StepExit.Host else: StepExit.Panic)
      if observed.value.exit == StepExit.Host: assert uint64(observed.value.hostCall) == 0
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

echo "PVM paper jump-table witnesses passed: 512; current width bounds; GP-PVM-006 recorded"
