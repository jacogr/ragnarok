# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay bounded public-API JamV1 observations from the pinned upstream VM generator.
import std/[assertions, syncio]
import ../../src/pvm/[program, machine, gas, step]
const UpstreamFrameBytes* = 249+8192+16384 ## Fixed CPU observations, bounded code and two page snapshots.

func word(data: openArray[byte], at, width: int): uint64 =
  ## Decode fields only after the caller validates the complete fixed header.
  result = 0
  for index in 0..<width:
    # Explicit byte expansion keeps the test format independent of production codecs.
    result = result or (uint64(data[at+index]) shl (index*8))

proc exerciseUpstreamFrame*(data: openArray[byte], preparedMode: bool = false): bool {.raises: [].} =
  ## False means malformed replay framing; admitted cases must satisfy every differential assertion.
  if data.len < 249+16384 or data.len > UpstreamFrameBytes: return false
  for index, value in [80'u8, 86, 77, 70, 85, 90, 48, 49]:
    # Literal magic prevents an unrelated saved input becoming an accepted comparison.
    if data[index] != value: return false
  let length = word(data, 8, 4)
  if length == 0 or length > 8192 or uint64(data.len) != 249+length+16384: return false
  if word(data, 12, 8) != 512 or data[20] notin {1'u8..4'u8}: return false
  let count = int(length)
  var wire = newSeq[byte](count)
  for index in 0..<count:
    # Only the admitted bounded extent is copied into the public JAM decoder.
    wire[index] = data[249+index]
  let decoded = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(8192), JumpCountLimit(256))
  assert decoded.error == ProgramError.None, "upstream JamV1 admission"
  var pages = default(array[2, PageImage])
  for page in 0..<2:
    # Two adjacent writable pages exercise both ordinary and cross-page scalar accesses.
    pages[page].index = PageIndex(uint32(16+page))
    pages[page].access = PageAccess.ReadWrite
    for offset in 0..<4096:
      # Initial and expected bytes occupy independent complete snapshots in the frame.
      pages[page].bytes[offset] = data[249+count+page*4096+offset]
  let captured = captureMemory(pages, PageLimit(2))
  assert captured.error == MachineError.None
  var initial = MachineInfo(pc: CodeAddress(0), gas: MachineGas(512))
  for index in 0..<13:
    # Register order is the public upstream Reg::ALL order, matching the JAM register indices.
    initial.registers[index] = RegisterValue(word(data, 41+index*8, 8))
  let source = captureMachine(decoded.value, captured.value, initial)
  assert source.error == MachineError.None
  let answer = if preparedMode:
      # Optional prepared execution consumes the exact same decoder owner, inputs and frozen reference observations.
      let created = newPreparedProgram(decoded.value, defaultPreparedLimits(GasCycleLimit(100000)))
      assert created.error == PreparationError.None
      execute(source.value, ExecutionStepLimit(100000), created.value)
    else: execute(source.value, ExecutionStepLimit(100000), GasCycleLimit(100000))
  assert answer.error == StepError.None, "local execution budget or API failure"
  let outcome = answer.value
  assert ord(outcome.exit) == int(data[20]), "upstream exit mismatch"
  let observed = machineInfo(outcome.machine)
  assert observed.error == MachineError.None
  let actual = observed.value
  if uint64(actual.gas) != word(data, 21, 8):
    # Retained logs distinguish pricing disagreements from instruction/register defects.
    echo "Gas actual=", uint64(actual.gas), " expected=", word(data, 21, 8)
  assert uint64(actual.gas) == word(data, 21, 8), "upstream gas mismatch"
  assert uint64(actual.gasDeficit) == 0
  let expectedPc = if outcome.exit in {StepExit.Panic, StepExit.Halt}: 0'u64 else: word(data, 29, 8)
  assert uint64(actual.pc) == expectedPc, "upstream PC mismatch"
  if outcome.exit == StepExit.Fault:
    # Compare the physical fault page; terminal Panic/Halt alone normalize PC to zero.
    assert uint64(uint32(outcome.faultPage)) == word(data, 37, 4), "upstream fault mismatch"
  else:
    assert word(data, 37, 4) == 0
  for index in 0..<13:
    # Every posterior register and every source register are independently inspected.
    assert uint64(actual.registers[index]) == word(data, 145+index*8, 8), "upstream register mismatch"
    assert uint64(machineInfo(source.value).value.registers[index]) == uint64(initial.registers[index])
  assert uint64(machineInfo(source.value).value.pc) == 0
  assert uint64(machineInfo(source.value).value.gas) == 512
  let posteriorMemory = memoryOf(outcome.machine)
  let sourceMemory = memoryOf(source.value)
  assert posteriorMemory.error == MachineError.None and sourceMemory.error == MachineError.None
  for page in 0..<2:
    # A write must neither change permissions nor mutate the original immutable memory owner.
    let posterior = pageImage(posteriorMemory.value, PageIndex(uint32(16+page)))
    let original = pageImage(sourceMemory.value, PageIndex(uint32(16+page)))
    assert posterior.error == MachineError.None and original.error == MachineError.None
    assert posterior.value.access == PageAccess.ReadWrite
    assert original.value.bytes == pages[page].bytes and original.value.access ==
        PageAccess.ReadWrite
    for offset in 0..<4096:
      # Compare both complete mapped pages even when the guest faults or runs out of gas.
      assert posterior.value.bytes[offset] == data[249+count+8192+page*4096+offset], "upstream memory mismatch"
  true
