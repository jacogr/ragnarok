# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete three-register destination-byte matrix preserves raw GP and explicit JAM values/prices.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, gas, step]

proc word(data: string, at: int): uint64 =
  ## Read one fixed u64 only after its enclosing complete corpus extent has been checked.
  result = 0
  for i in 0..<8:
    # Expected record framing never invokes the production decoder.
    result = result or (uint64(byte(data[at + i])) shl (8 * i))

var data = ""
try:
  # Frozen inputs are required; ordinary native verification never runs a Rust generator.
  data = readFile(getEnv("RAGNAROK_PVM_DESTINATION"))
except:
  quit 2
assert data.len == 116 + 31488 * 52 and data[0..7] == "PVMDST01"
let count = uint64(byte(data[8])) + (uint64(byte(data[9])) shl 8) +
  (uint64(byte(data[10])) shl 16) + (uint64(byte(data[11])) shl 24)
assert count == 31488
let memory = captureMemory([], PageLimit(0)).value
var differences = 0
for row in 0..<31488:
  # Fixed record extents are established globally before any row field is decoded.
  let at = 116 + row * 52
  let opcode = byte(data[at])
  let descriptor = byte(data[at + 1])
  let encoded = byte(data[at + 2])
  let variant = int(byte(data[at + 3]))
  assert opcode in {190'u8..230'u8} and variant < 3
  let paperDestination = min(12, int(encoded))
  let jamDestination = min(12, int(encoded) mod 16)
  if paperDestination != jamDestination: inc differences
  var registers = default(RegisterFile)
  for i in 0..<13:
    # A shared frozen input table has three deterministic rotations, independent of either decoder.
    registers[i] = RegisterValue(word(data, 12 + ((i + 3 * variant) mod 13) * 8))
  var wire = @[0'u8, 0, 4, opcode, descriptor, encoded, 0, 9]
  let paper = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0)).value
  let jam = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(32), JumpCountLimit(0)).value
  let owners = [paper, jam]
  for i in 0..<wire.len:
    # Both independently captured owners retain original bytes and their private profile after release/mutation.
    wire[i] = 0
  for profile in 0..<2:
    # Paper and JAM decode the same original operand byte without changing code or bitmap offsets.
    let owner = owners[profile]
    let decoded = instruction(owner, CodeAddress(0)).value
    let destination = if profile == 0: paperDestination else: jamDestination
    assert decoded.opcode == opcode and decoded.shape == OperandShape.ThreeRegisters and
        decoded.skip == 2
    assert int(byte(decoded.d)) == destination
    let value = word(data, at + (if profile == 0: 4 else: 12))
    let price = word(data, at + (if profile == 0: 20 else: 36))
    let cycles = word(data, at + (if profile == 0: 28 else: 44))
    assert price > 0 and price < 1000 and cycles > 0 and cycles < 1000
    assert uint64(blockGas(owner, CodeAddress(0), GasCycleLimit(cycles)).value) == price
    assert blockGas(owner, CodeAddress(0), GasCycleLimit(cycles - 1)).error ==
        GasError.CycleLimitExceeded
    let initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(price + 7),
      blockCharged: false, registers: registers)
    let source = captureMachine(owner, memory, initial).value
    let stepped = stepRegisters(source, GasCycleLimit(cycles))
    assert stepped.error == StepError.None and stepped.value.exit == StepExit.Continued
    let actual = machineInfo(stepped.value.machine).value
    assert uint64(actual.pc) == 3 and uint64(actual.gas) == 7 and actual.blockCharged
    for i in 0..<13:
      # Full posterior registers expose wrong targets even when a scalar result happens to match a sentinel.
      assert uint64(actual.registers[i]) == (if i == destination: value else: uint64(registers[i]))
      assert uint64(machineInfo(source).value.registers[i]) == uint64(registers[i])
    let poor = captureMachine(owner, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(price - 1),
      blockCharged: false, registers: registers)).value
    let refused = stepRegisters(poor, GasCycleLimit(cycles)).value
    assert refused.exit == StepExit.OutOfGas
    let unchanged = machineInfo(refused.machine).value
    assert uint64(unchanged.pc) == 0 and uint64(unchanged.gas) == price - 1 and
        not unchanged.blockCharged
    for i in 0..<13:
      # Affordability precedes destination selection and cannot leak a partially changed register.
      assert uint64(unchanged.registers[i]) == uint64(registers[i])
assert differences == 22140

echo "PVM destination-byte reference passed: 31488 rows, 22140 scoped differences"
