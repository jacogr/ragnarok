# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native replay of independent integer arithmetic and pinned upstream scalar witnesses.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, machine, registers]

# Decode a fixed little-endian fixture word; the fixture shape is checked before any access.
proc word(data: string, at: int): uint64 =
  result = 0
  # Test-only serialization is independent of the production instruction decoder.
  for i in 0..<8: result = result or (uint64(byte(data[at + i])) shl (8 * i))

# Build one instruction followed by a terminating trap, marking exact byte positions independently.
proc programFor(op, descriptor, destination: byte, immediate: uint64): Program =
  var code = @[op, descriptor]
  if op == 20:
    # Extended load uses eight literal bytes regardless of signed compact widths.
    for i in 0..<8: code.add(byte((immediate shr (8 * i)) and 255))
  elif op == 51 or op in 131'u8..161'u8:
    # Four-byte immediates must sign-extend in the decoder, not the arithmetic evaluator.
    for i in 0..<4: code.add(byte((immediate shr (8 * i)) and 255))
  elif op in 190'u8..230'u8:
    # The whole third byte is the saturated destination index.
    code.add(destination)
  let ending = code.len
  code.add(0)
  var bytes = @[0'u8, 0, byte(code.len)]
  # Code lengths here fit a single canonical natural byte.
  for value in code: bytes.add(value)
  var mask = newSeq[byte]((code.len + 7) div 8)
  mask[0] = 1
  mask[ending div 8] = mask[ending div 8] or (1'u8 shl (ending mod 8))
  # Append the independently constructed opcode mask after the code bytes.
  for value in mask: bytes.add(value)
  let captured = decodeProgram(bytes, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0))
  assert captured.error == ProgramError.None
  captured.value

var data = ""
# Fixture I/O failure must fail the suite rather than silently skip corpus coverage.
try:
  data = readFile(getEnv("RAGNAROK_PVM_REGISTERS"))
except:
  # An unavailable or unreadable fixed corpus is a setup failure.
  quit 2
assert data.len >= 12 and data[0..7] == "PVMREG01"
var count = 0
# The count is bounded by the checked file extent before any record is consumed.
for i in 0..<4: count = count or (int(byte(data[8 + i])) shl (8 * i))
assert count > 32000 and (data.len - 12) mod 51 == 0 and count == (data.len - 12) div 51
var seen: array[256, bool] = default(array[256, bool])
# Every fixture runs through a real decoded program and compares all thirteen registers.
for row in 0..<count:
  let at = 12 + row * 51
  let op = byte(data[at])
  let descriptor = byte(data[at + 1])
  let encodedDestination = byte(data[at + 2])
  let immediate = word(data, at + 3)
  var input = default(RegisterFile)
  # Initialize every fixed register before applying variable witness inputs.
  for i in 0..<13: input[i] = RegisterValue(uint64(100 + i))
  # Overlay the four independently specified varying registers.
  for slot in 0..<4:
    # Variable registers occupy 0, 1, 2 and the saturation destination 12.
    let index = (if slot == 3: 12 else: slot)
    input[index] = RegisterValue(word(data, at + 11 + slot * 8))
  let original = input
  let expected = word(data, at + 43)
  var destination = min(12, int(encodedDestination))
  if op in 100'u8..110'u8 or op == 20 or op == 51 or op in 131'u8..161'u8:
    # All these families encode their destination in the low descriptor nibble.
    destination = min(12, int(descriptor mod 16))
  let program = programFor(op, descriptor, encodedDestination, immediate)
  let evaluated = evaluateRegisters(program, CodeAddress(0), input)
  assert evaluated.error == RegisterError.None
  let output = evaluated.value
  let decoded = instruction(program, CodeAddress(0))
  let written = evaluateRegisterWrite(decoded, input)
  assert written.error == RegisterError.None
  assert int(byte(written.destination)) == destination and uint64(written.writeValue) == expected
  let retainedWrite = written
  var changedInput = input
  changedInput[destination] = RegisterValue(not expected)
  assert uint64(retainedWrite.writeValue) == expected # The scalar result owns copied bits, with no alias into either array.
  let reused = evaluateRegisters(decoded, input)
  assert reused.error == RegisterError.None
  for index in 0..<13:
    # Only the selected destination may differ, and the input array must remain untouched.
    assert uint64(input[index]) == uint64(original[index])
    let wanted = (if index == destination: expected else: uint64(original[index]))
    # A failure identifies its exact frozen witness for reproducible diagnosis.
    if uint64(output[index]) != wanted:
      echo "register witness ", row, " opcode ", op, " register ", index
    assert uint64(output[index]) == wanted
    assert uint64(reused.value[index]) == wanted
  seen[int(op)] = true

# All 85 implemented opcodes must have actual oracle coverage.
var covered = 0
for op in 0..<256:
  # Only opcodes actually replayed contribute to coverage.
  if seen[op]: inc covered
assert covered == 85
let missingWrite = default(RegisterWriteResult)
assert missingWrite.error == RegisterError.Uninitialized
let missingDecode = default(ProgramResult[Instruction])
assert evaluateRegisterWrite(missingDecode, default(RegisterFile)).error ==
    RegisterError.InvalidInstruction
let missingResult = default(RegisterResult)
assert missingResult.error == RegisterError.Uninitialized
assert evaluateRegisters(default(Program), CodeAddress(0), default(RegisterFile)).error ==
  RegisterError.InvalidInstruction
let missingInstruction = default(ProgramResult[Instruction])
assert evaluateRegisters(missingInstruction, default(RegisterFile)).error ==
  RegisterError.InvalidInstruction
let valid = programFor(200, 0x10, 2, 0)
assert evaluateRegisters(instruction(valid, CodeAddress(1)), default(RegisterFile)).error ==
  RegisterError.InvalidInstruction
assert evaluateRegisters(valid, CodeAddress(1), default(RegisterFile)).error ==
  RegisterError.InvalidInstruction
assert evaluateRegisters(valid, CodeAddress(high(uint64)), default(RegisterFile)).error ==
  RegisterError.InvalidInstruction
# Every valid out-of-scope opcode is rejected explicitly, including memory and control-flow operations.
for op in 0..255:
  # Valid decoded instructions outside the evaluator must fail without a payload.
  if validOpcode(byte(op)) and not seen[op]:
    let unsupported = programFor(byte(op), 0, 0, 0)
    assert evaluateRegisterWrite(instruction(unsupported, CodeAddress(0)), default(
        RegisterFile)).error == RegisterError.UnsupportedInstruction
    assert evaluateRegisters(unsupported, CodeAddress(0), default(RegisterFile)).error ==
      RegisterError.UnsupportedInstruction
    assert evaluateRegisters(instruction(unsupported, CodeAddress(0)), default(
        RegisterFile)).error ==
      RegisterError.UnsupportedInstruction

# Extracting and mutating a returned array cannot change its result or another extraction.
let copyResult = evaluateRegisters(valid, CodeAddress(0), default(RegisterFile))
assert copyResult.error == RegisterError.None
var copiedRegisters = copyResult.value
copiedRegisters[2] = RegisterValue(99)
assert uint64(copyResult.value[2]) == 0

# A validated scalar instruction result remains independent of extracted copies and released owners.
block validatedResultOwnership:
  var owner = programFor(200, 0x10, 2, 0)
  let decoded = instruction(owner, CodeAddress(0))
  owner = default(Program)
  var changed = decoded.value
  changed.opcode = 0
  changed.d = RegisterIndex(255)
  assert decoded.value.opcode == 200 and byte(decoded.value.d) == 2
  var input = default(RegisterFile)
  input[0] = RegisterValue(7)
  input[1] = RegisterValue(11)
  let completed = evaluateRegisters(decoded, input)
  assert completed.error == RegisterError.None
  for i in 0..<13:
    # Exactly D changes after owner release; copying an instruction never opens a mutable result alias.
    let expected = if i == 2: 18'u64 else: uint64(input[i])
    assert uint64(completed.value[i]) == expected

echo "PVM register operations passed"
