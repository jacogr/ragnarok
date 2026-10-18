# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Replay independent GP pipeline fixtures, including exact cycle-budget boundaries.
import std/[assertions, syncio, envvars]
import ../../../src/pvm/[program, gas]

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
# The signed branch target -1 is not defined by the GP's right-hand zero suffix.
let negative = decodeProgram([0'u8, 0, 7, 170, 0, 255, 255, 255, 255, 0, 65],
  CodeAddress(0), ProgramByteLimit(11), JumpCountLimit(0))
assert negative.error == ProgramError.None
assert blockGas(negative.value, CodeAddress(0), GasCycleLimit(100)).error ==
  GasError.NegativeBranchTarget
# A backward branch to an in-range unlikely byte is priced normally, not rejected by the gate.
let backward = decodeProgram([0'u8, 0, 8, 2, 170, 0, 255, 255, 255, 255, 0, 131],
  CodeAddress(0), ProgramByteLimit(12), JumpCountLimit(0))
assert backward.error == ProgramError.None
let backwardCost = blockGas(backward.value, CodeAddress(0), GasCycleLimit(43))
assert backwardCost.error == GasError.None and uint64(backwardCost.value) == 40
assert blockGas(backward.value, CodeAddress(0), GasCycleLimit(42)).error ==
  GasError.CycleLimitExceeded
echo "PVM gas tests passed"
