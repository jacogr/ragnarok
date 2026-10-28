# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Original metered fault/repair/retry witnesses preserve paid block gas and all prefix/source state.

import std/assertions
import std/syncio
import ../../../src/pvm/program as pvm_program
import ../../../src/pvm/machine as pvm_machine
import ../../../src/pvm/gas as pvm_gas
import ../../../src/pvm/step as pvm_step

for opcode in 52'u8..62'u8:
  for access in [PageAccess.ReadWrite, PageAccess.ReadOnly]:
    # Explicit opcode boundaries and four-byte -1 address match the public reference tool verbatim.
    let wire = [0'u8, 0, 11, 51, 8, 11, opcode, 7, 255, 255, 255, 255, 50, 0, 9, 2]
    let program = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0)).value
    assert uint64(blockGas(program, CodeAddress(0), GasCycleLimit(28)).value) == 25
    let oneLess = blockGas(program, CodeAddress(0), GasCycleLimit(27))
    assert oneLess.error == GasError.CycleLimitExceeded
    var registers = default(RegisterFile)
    registers[0] = RegisterValue(0xffff0000'u64)
    registers[7] = RegisterValue(99)
    registers[8] = RegisterValue(77)
    let originalMemory = captureMemory([], PageLimit(1)).value
    let source = captureMachine(program, originalMemory, MachineInfo(pc: CodeAddress(0),
      gas: MachineGas(32), blockCharged: false, registers: registers)).value
    let first = execute(source, ExecutionStepLimit(2), GasCycleLimit(28))
    assert first.error == StepError.None and first.value.exit == StepExit.Fault
    assert uint32(first.value.faultPage) == 0xfffff000'u32
    let stopped = machineInfo(first.value.machine).value
    assert uint64(stopped.pc) == 3 and uint64(stopped.gas) == 7 and stopped.blockCharged
    var image = PageImage(index: PageIndex(0xfffff), access: access,
      bytes: default(array[4096, byte]))
    for index in 0..<4096: image.bytes[index] = 7
    let repairedMemory = captureMemory([image], PageLimit(1)).value
    let repaired = captureMachine(program, repairedMemory, stopped).value
    let retried = stepMemory(repaired, GasCycleLimit(0)).value
    assert retried.exit == StepExit.Panic
    assert uint64(machineInfo(retried.machine).value.pc) == 3
    let completed = execute(repaired, ExecutionStepLimit(1), GasCycleLimit(0)).value
    assert completed.exit == StepExit.Panic
    let final = machineInfo(completed.machine).value
    assert uint64(final.pc) == 0 and uint64(final.gas) == 7 and final.blockCharged
    for index in 0..<13:
      # Only the completed prefix changes r8; failed memory instructions and repairs write no registers.
      let expected = if index == 8: 11'u64 else: uint64(registers[index])
      assert uint64(stopped.registers[index]) == expected
      assert uint64(final.registers[index]) == expected
      assert uint64(machineInfo(source).value.registers[index]) == uint64(registers[index])
    assert pageImage(memoryOf(completed.machine).value, PageIndex(0xfffff)).value.bytes == image.bytes
    assert pageImage(memoryOf(completed.machine).value, PageIndex(0xfffff)).value.access == access
    assert pageImage(repairedMemory, PageIndex(0xfffff)).value.bytes == image.bytes
    assert pageImage(originalMemory, PageIndex(0xfffff)).value.access == PageAccess.Inaccessible
    assert pageImage(memoryOf(first.value.machine).value, PageIndex(0xfffff)).value.bytes ==
        default(array[4096, byte])
    assert uint64(machineInfo(source).value.gas) == 32 and not machineInfo(
        source).value.blockCharged

echo "PVM metered fault-repair/retry reference passed: 22"
