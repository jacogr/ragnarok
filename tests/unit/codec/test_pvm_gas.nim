# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native gas tests replay independent GP pipeline fixtures and exact cycle-budget boundaries.
## The executable reads RAGNAROK_PVM_GAS, checks blockGas and reports a failing exit on mismatch.

import std/[assertions, syncio, envvars]
import ../../../src/pvm/program
import ../../../src/pvm/gas/gas
import ../../../src/pvm/[machine, step]

# Decode a bounded little-endian test word without using production codecs.
proc word(data: string, at, width: int): uint64 =
  result = 0
  # Callers check record extents before this fixed-width read.
  for i in 0..<width: result = result or (uint64(byte(data[at + i])) shl (8 * i))

var data = ""
# A missing fixture is a failing setup, never an omitted gas corpus.
try:
  data = readFile(getEnv("RAGNAROK_PVM_GAS"))
except:
  # Preserve I/O failure as a nonzero native suite exit.
  quit 2
assert data.len >= 12 and data[0..7] == "PVMGAS01"
let count = int(word(data, 8, 4))
assert count >= 1000
var cursor = 12
# Every row uses real program decoding and independently frozen gas and cycle counts.
for row in 0..<count:
  assert data.len - cursor >= 24
  let start = word(data, cursor, 4)
  let expected = word(data, cursor + 4, 8)
  let cycles = word(data, cursor + 12, 8)
  let length = int(word(data, cursor + 20, 4))
  cursor += 24
  assert length <= data.len - cursor
  var bytes = newSeq[byte](length)
  # Copy the serialized fixture into independently owned input bytes.
  for i in 0..<length: bytes[i] = byte(data[cursor + i])
  cursor += length
  let captured = decodeProgram(bytes, CodeAddress(start), ProgramByteLimit(uint64(length)),
    JumpCountLimit(0))
  assert captured.error == ProgramError.None
  let price = blockGas(captured.value, CodeAddress(start), GasCycleLimit(cycles))
  if price.error != GasError.None or uint64(price.value) != expected:
    # Report the stable fixture ordinal before failing so regressions are directly reproducible.
    echo "gas fixture failure: ", row
    assert false
  assert cycles > 0
  assert blockGas(captured.value, CodeAddress(start), GasCycleLimit(cycles - 1)).error ==
    GasError.CycleLimitExceeded
  assert blockGas(captured.value, CodeAddress(start), GasCycleLimit(high(uint64))).error ==
    GasError.None
assert cursor == data.len
let uninitialized = default(GasResult)
assert uninitialized.error == GasError.Uninitialized
assert blockGas(default(Program), CodeAddress(0), GasCycleLimit(100)).error == GasError.InvalidStart
# A move followed by trap has one interior instruction and an unmarked register descriptor.
let captured = decodeProgram([0'u8, 0, 3, 100, 0, 0, 5], CodeAddress(0),
  ProgramByteLimit(7), JumpCountLimit(0))
assert captured.error == ProgramError.None
assert blockGas(captured.value, CodeAddress(1), GasCycleLimit(100)).error == GasError.InvalidStart
assert blockGas(captured.value, CodeAddress(2), GasCycleLimit(100)).error == GasError.InvalidStart
assert blockGas(captured.value, CodeAddress(high(uint64)), GasCycleLimit(100)).error ==
  GasError.InvalidStart
assert instructionByte(captured.value, CodeAddress(1)).value == 0
assert instructionByte(captured.value, CodeAddress(high(uint64))).value == 0
assert instructionByte(default(Program), CodeAddress(0)).error == ProgramError.InvalidOwner
# PolkaVM wraps the negative static target before pricing; noncheap move fallthrough isolates the absent-target hit.
let negative = decodeProgram([0'u8, 0, 9, 170, 0, 255, 255, 255, 255, 100, 0, 0, 65, 1],
  CodeAddress(0), ProgramByteLimit(14), JumpCountLimit(0))
assert negative.error == ProgramError.None
let negativeCost = blockGas(negative.value, CodeAddress(0), GasCycleLimit(4))
assert negativeCost.error == GasError.None and uint64(negativeCost.value) == 1
assert blockGas(negative.value, CodeAddress(0), GasCycleLimit(3)).error ==
    GasError.CycleLimitExceeded
# A backward branch to an in-range unlikely byte is priced normally with its actual target byte.
let backward = decodeProgram([0'u8, 0, 8, 2, 170, 0, 255, 255, 255, 255, 0, 131],
  CodeAddress(0), ProgramByteLimit(12), JumpCountLimit(0))
assert backward.error == ProgramError.None
let backwardCost = blockGas(backward.value, CodeAddress(0), GasCycleLimit(43))
assert backwardCost.error == GasError.None and uint64(backwardCost.value) == 40
assert blockGas(backward.value, CodeAddress(0), GasCycleLimit(42)).error ==
  GasError.CycleLimitExceeded
# Grey issue155: only post-terminator PCs define gas blocks, even if later jumps name interior opcodes.
for target in [0, 1, 2, 3, 4, 8, 9, 100]:
  let displacement = byte((target - 9 + 256) mod 256)
  let wire = [0'u8, 0, 11, 51, 7, 7, 59, 7, 0, 0, 3, 0, 40, displacement, 9, 3]
  let boundary = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(64), JumpCountLimit(0)).value
  assert not basicBlockStart(boundary, CodeAddress(3)).value
  assert uint64(containingBlockStart(boundary, CodeAddress(3)).value) == 0
  assert blockGas(boundary, CodeAddress(3), GasCycleLimit(100)).error == GasError.InvalidStart
  assert uint64(blockGas(boundary, CodeAddress(0), GasCycleLimit(29)).value) == 26
  assert blockGas(boundary, CodeAddress(0), GasCycleLimit(28)).error == GasError.CycleLimitExceeded
  var image = PageImage(index: PageIndex(48), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  image.bytes[0] = 11
  let memory = captureMemory([image], PageLimit(1)).value
  var registers = default(RegisterFile)
  registers[7] = RegisterValue(99)
  for fuel in [25'u64, 26]:
    let source = captureMachine(boundary, memory, MachineInfo(pc: CodeAddress(0), gas: MachineGas(fuel),
      blockCharged: false, registers: registers)).value
    let result = execute(source, ExecutionStepLimit(3), GasCycleLimit(29)).value
    if fuel == 25:
      # Whole-block affordability precedes even the successful prefix load and the later store.
      assert result.exit == StepExit.OutOfGas
      assert uint64(machineInfo(result.machine).value.gas) == 25
      assert uint64(machineInfo(result.machine).value.registers[7]) == 99
      assert uint64(load(memoryOf(result.machine).value, MemoryAddress(196608), AccessWidth(
          1)).value) == 11
    else:
      assert result.exit == StepExit.Panic
      assert uint64(machineInfo(result.machine).value.gas) == 0
      assert uint64(machineInfo(result.machine).value.registers[7]) == 7
      assert uint64(load(memoryOf(result.machine).value, MemoryAddress(196608), AccessWidth(
          1)).value) == 7
    assert uint64(machineInfo(source).value.registers[7]) == 99
    assert uint64(load(memory, MemoryAddress(196608), AccessWidth(1)).value) == 11

proc saturatedPipeline(repetitions: int): Program =
  ## Frame an original mixed-resource block independently; all counts stay below4096 code bytes.
  var bytes: seq[byte] = @[]
  var starts: seq[int] = @[]
  let group = [@[10'u8], @[2'u8], @[52'u8, 1], @[59'u8, 1], @[202'u8, 33, 3],
    @[203'u8, 33, 4], @[197'u8, 33, 5], @[218'u8, 33, 6], @[200'u8, 33, 7], @[100'u8, 115]]
  for repeat in 0..<repetitions:
    for part in group:
      # Host/unlikely reach100/40 cycles; load/store/multiply/divide contend with ALU and rename consumers.
      starts.add(bytes.len)
      for octet in part: bytes.add(octet)
  starts.add(bytes.len)
  bytes.add(0)
  assert bytes.len > 0 and bytes.len < 4096
  var wire = @[0'u8, 0]
  if bytes.len < 128:
    wire.add(byte(bytes.len)) # Canonical one-byte size covers the smallest resource witness.
  else:
    wire.add(byte(128+(bytes.len shr 8))) # Larger blocks use exactly the two-byte natural encoding.
    wire.add(byte(bytes.len and 255))
  for octet in bytes: wire.add(octet)
  var mask = newSeq[byte]((bytes.len+7) div 8)
  for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
  for octet in mask: wire.add(octet)
  let captured = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(8192), JumpCountLimit(0))
  assert captured.error == ProgramError.None
  captured.value

for witness in [(repetitions: 1, price: 100'u64, cycles: 103'u64),
    (repetitions: 4, price: 276'u64, cycles: 279'u64),
    (repetitions: 32, price: 1956'u64, cycles: 1959'u64),
    (repetitions: 33, price: 2016'u64, cycles: 2019'u64),
    (repetitions: 65, price: 3936'u64, cycles: 3939'u64)]:
  # Literal simultaneous-transition reference prices protect saturation, full-buffer pressure and repeated resource release.
  let program = saturatedPipeline(witness.repetitions)
  let completed = blockGas(program, CodeAddress(0), GasCycleLimit(witness.cycles))
  assert completed.error == GasError.None and uint64(completed.value) == witness.price
  assert blockGas(program, CodeAddress(0), GasCycleLimit(witness.cycles-1)).error ==
      GasError.CycleLimitExceeded

echo "PVM gas tests passed"
