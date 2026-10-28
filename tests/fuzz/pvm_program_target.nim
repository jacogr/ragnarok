# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded raw/JAM deblob fuzz properties inspect copied instructions, huge indices and immutable ownership without executing guest code.
import std/assertions
import ../../src/pvm/program as pvm_program
const ProgramFuzzBytes* = 1024 ## Includes the test-only profile/resource selector; no file or callback may allocate from a larger untrusted extent.
proc sameInstruction(actual, expected: Instruction) =
  ## Every scalar operand and instruction identity must remain independent of caller buffer mutation.
  assert uint64(actual.address) == uint64(expected.address)
  assert actual.opcode == expected.opcode and actual.shape == expected.shape and actual.skip == expected.skip
  assert byte(actual.a) == byte(expected.a) and byte(actual.b) == byte(expected.b) and byte(
      actual.d) == byte(expected.d)
  assert uint64(actual.x) == uint64(expected.x) and uint64(actual.y) == uint64(expected.y)
  assert actual.displacement == expected.displacement
proc exerciseProgramBytes*(data: openArray[byte]): bool {.raises: [].} =
  ## False is an ordinary complete decoder refusal; assertions expose inconsistent successful snapshots or ownership/range defects.
  if data.len == 0 or data.len > ProgramFuzzBytes: return false
  let selector = data[0]
  var input = newSeq[byte](data.len-1)
  for index in 0..<input.len: input[index] = data[index+1]
  let bytes = ProgramByteLimit(if (selector and 2) == 0: uint64(ProgramFuzzBytes-1) else: 0'u64)
  let jumps = JumpCountLimit(if (selector and 4) == 0: 16'u64 else: 0'u64)
  let decoded = if (selector and 1) == 0:
      decodeProgram(input, CodeAddress(0), bytes, jumps)
    else: decodeJamProgram(input, CodeAddress(0), bytes, jumps)
  assert decoded.error != ProgramError.Uninitialized
  if decoded.error != ProgramError.None: return false
  let program = decoded.value
  let length = codeLength(program)
  assert length.error == ProgramError.None and length.value > 0 and length.value <= uint64(input.len)
  let count = int(length.value) # The admitted input extent proves the native allocation/index conversion.
  var original = newSeq[byte](count)
  let first = instruction(program, CodeAddress(0))
  assert first.error == ProgramError.None
  let jump = jumpTarget(program, JumpIndex(0))
  assert jump.error in {ProgramError.None, ProgramError.InvalidIndex}
  for index in 0..<count:
    let address = CodeAddress(uint64(index))
    original[index] = instructionByte(program, address).value
    let opcode = instructionOpcode(program, address)
    let item = instruction(program, address)
    assert opcode.error == item.error # Only marked instruction bytes may be decoded; operands remain ordinary bytes.
    if item.error == ProgramError.None:
      assert uint64(item.value.address) == uint64(index) and item.value.opcode == opcode.value
      assert item.value.opcode == original[index] and validOpcode(item.value.opcode)
      let start = containingBlockStart(program, address)
      assert start.error == ProgramError.None and uint64(start.value) <= uint64(index)
      assert basicBlockStart(program, start.value).value
  for index in 0..<input.len: input[index] = 0 # Captured code, masks, operands and jump bytes cannot borrow this now-mutated caller storage.
  assert codeLength(program).value == length.value
  sameInstruction(instruction(program, CodeAddress(0)).value, first.value)
  let retainedJump = jumpTarget(program, JumpIndex(0))
  assert retainedJump.error == jump.error
  if jump.error == ProgramError.None: assert uint64(retainedJump.value) == uint64(jump.value)
  for index in 0..<count:
    assert instructionByte(program, CodeAddress(uint64(index))).value == original[index]
  for address in [uint64(count), high(uint64)]:
    assert instruction(program, CodeAddress(address)).error == ProgramError.InvalidInstruction
    assert instructionOpcode(program, CodeAddress(address)).error == ProgramError.InvalidInstruction
    assert instructionByte(program, CodeAddress(address)).value ==
        0 # Normative zero suffix is distinct from executable entry validation.
  assert jumpTarget(program, JumpIndex(high(uint64))).error == ProgramError.InvalidIndex
  true
