# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Lazy stream metadata can refuse under a real heap cap after bytecode admission succeeds.

import std/[assertions, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, step]
import ../../../src/pvm/gas/gas

const CodeLength = 512*1024
var wire = default(array[5+CodeLength+CodeLength div 8, byte])
let size = encode(JamNatural(CodeLength))
assert size.len == 3
for i in 0..<size.len: wire[2+i] = size.bytes[i]
# Every code byte is a trap. The only executed block has one instruction.
for i in 5+CodeLength..<wire.len: wire[i] = 255
let decoded = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(uint64(wire.len)),
  JumpCountLimit(0))
assert decoded.error == ProgramError.None
let owner = decoded.value
let admitted = newPreparedProgram(owner, defaultPreparedLimits(GasCycleLimit(10000)))
assert admitted.error == PreparationError.None
let prepared = admitted.value
let memory = captureMemory([], PageLimit(0)).value
let info = MachineInfo(pc: CodeAddress(0), gas: MachineGas(100))
let source = captureMachine(owner, memory, info).value
block:
  # Leave enough room for the derived directories but refuse a lazy fact chunk.
  let pressure = newSeq[byte](300*1024)
  assert pressure.len == 300*1024, "pressure setup"
  let result = execute(source, ExecutionStepLimit(1), prepared)
  assert result.error == StepError.InvalidPreparedProgram, "stream allocation refusal"
  assert pressure[0] == 0
assert machineInfo(source).value == info
assert preparedInfo(prepared).value.streamNodes == 0
let retried = execute(source, ExecutionStepLimit(1), prepared)
assert retried.error == StepError.None and retried.value.exit == StepExit.Panic
assert uint64(machineInfo(retried.value.machine).value.gas) == 100-uint64(
  blockGas(owner, CodeAddress(0), GasCycleLimit(10000)).value)
echo "PVM stream allocation refusal passed"
