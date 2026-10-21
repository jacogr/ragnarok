# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay independent complete conditional-control paths and invalid successors against all CPU registers.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, gas, step]

proc word(data: string, at, width: int): uint64 =
  ## Read fixed little-endian fixture fields after their caller proves the complete record extent.
  result = 0
  for index in 0..<width: result = result or (uint64(byte(data[at+index])) shl (8*index))

var data = ""
try:
  data = readFile(getEnv("RAGNAROK_PVM_CONTROL"))
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVMCTL01"
let count = int(word(data, 8, 4))
assert count >= 384 and count <= 4096
var cursor = 12
for row in 0..<count:
  assert data.len-cursor >= 217
  let length = int(word(data, cursor, 4))
  let exit = byte(data[cursor+4])
  let referencePc = word(data, cursor+5, 4)
  assert exit <= 1 and length <= 64
  var registers = default(RegisterFile)
  var expected = default(RegisterFile)
  for index in 0..<13:
    registers[index] = RegisterValue(word(data, cursor+9+index*8, 8))
    expected[index] = RegisterValue(word(data, cursor+113+index*8, 8))
  cursor += 217
  assert length <= data.len-cursor
  var wire = newSeq[byte](length)
  for index in 0..<length: wire[index] = byte(data[cursor+index])
  cursor += length
  let program = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(1)).value
  let source = captureMachine(program, captureMemory([], PageLimit(0)).value,
    MachineInfo(pc: CodeAddress(0), gas: MachineGas(10000), blockCharged: false,
      registers: registers)).value
  let answer = execute(source, ExecutionStepLimit(4), GasCycleLimit(1000))
  assert answer.error == StepError.None
  assert answer.value.exit == (if exit == 0: StepExit.Halt else: StepExit.Panic)
  assert uint64(machineInfo(answer.value.machine).value.pc) == 0
  for index in 0..<13:
    if uint64(machineInfo(answer.value.machine).value.registers[index]) != uint64(expected[index]):
      echo "control register mismatch: row=", row, " register=", index
      assert false
    assert uint64(machineInfo(source).value.registers[index]) == uint64(registers[index])
  var traced = source
  var stopped = false
  for attempt in 0..<4:
    # Compare the causing PC and the GP single-step PC before recursive exit normalization.
    let observed = stepOnce(traced, GasCycleLimit(1000)).value
    if observed.exit in {StepExit.Panic, StepExit.Halt}:
      assert observed.exit == (if exit == 0: StepExit.Halt else: StepExit.Panic)
      if exit == 1:
        let before = machineInfo(traced).value.pc
        let item = instruction(program, before).value
        if item.opcode == 0:
          # GP single-step trap advances by default; PolkaVM reports the causing instruction PC.
          assert uint64(before) == referencePc
          assert uint64(machineInfo(observed.machine).value.pc) == referencePc+1+uint64(item.skip)
        else:
          assert uint64(machineInfo(observed.machine).value.pc) == referencePc
      else:
        assert referencePc == 0xffffffff'u64
      stopped = true
      break
    assert observed.exit == StepExit.Continued
    traced = observed.machine
  assert stopped
  assert uint64(machineInfo(source).value.pc) == 0
  assert uint64(machineInfo(source).value.gas) == 10000 and not machineInfo(
      source).value.blockCharged
assert cursor == data.len
echo "PVM control-flow reference passed: ", count
