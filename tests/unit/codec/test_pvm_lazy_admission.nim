# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unvisited facts stay unfilled; private catalogues preserve global ordinals and stream isolation.

import std/[assertions, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
import ../../../src/pvm/internal/handler_stream

proc literalProgram(): Program =
  ## Independent literal framing creates 1,024 isolated two-instruction blocks.
  var bytes = @[0'u8, 0'u8]
  let length = encode(JamNatural(4096))
  for index in 0..<length.len: bytes.add(length.bytes[index])
  for blockIndex in 0..<1024:
    # Each load-immediate followed by trap gives a distinct block with observable register output.
    bytes.add(51'u8)
    bytes.add(7'u8)
    bytes.add(byte(blockIndex mod 127))
    bytes.add(0'u8)
  for index in 0..<512: bytes.add(0x99'u8) # Literal starts at offsets 0, 3, 4, 7 in each byte.
  let admitted = decodeJamProgram(bytes, CodeAddress(0), ProgramByteLimit(8192), JumpCountLimit(0))
  assert admitted.error == ProgramError.None
  admitted.value

proc frame(plan: FlatPlan, blockIndex: int, interior: bool = false): FlatFrame =
  ## Select an arbitrary genuine block or its prepaid-capable interior without sharing a catalogue.
  newFlatFrame(plan, [], MachineInfo(pc: CodeAddress(uint64(blockIndex*4+int(interior)*3)),
    gas: MachineGas(100), registers: default(RegisterFile)))

proc checkRun(current: var FlatFrame, blockIndex: int, interior: bool = false) =
  ## Cold and reused entries retain full containing-block gas and exact instruction effects.
  runFlat(current, if interior: 1'u64 else: 2'u64)
  assert current.reason == StepError.None and current.exit == StepExit.Panic
  assert uint64(current.info.gas) == 98 and current.info.blockCharged
  assert uint64(current.info.registers[7]) == (if interior: 0'u64 else: uint64(blockIndex mod 127))

let source = literalProgram()
let plan = newFlatPlan(source, GasCycleLimit(10000))
assert planFacts(plan) == 2048
# A valid frame with an empty executable cache hands back no derived metadata.
var emptyFrame = frame(plan, 0)
var emptyStream = takeFlatStream(emptyFrame)
assert materializedFacts(emptyFrame) == 0 and materializedFacts(emptyStream) == 0

var first = frame(plan, 700)
var independent = frame(plan, 100)
assert materializedFacts(first) == 0 and materializedFacts(independent) == 0
checkRun(first, 700)
assert materializedFacts(first) == 2 and materializedFacts(independent) == 0
# Native adjacency proofs require source-global ordinals even when the first visited block is late.
assert materializedOrdinal(first, CodeAddress(2800)) == 1401
assert materializedOrdinal(first, CodeAddress(2803)) == 1402
assert materializedOrdinal(first, CodeAddress(1200)) == 0
assert planFacts(plan) == 2048
var saved = takeFlatStream(first)
assert materializedFacts(first) == 0 and materializedFacts(saved) == 2
var earlier = frame(plan, 300)
restoreFlatStream(earlier, saved)
assert materializedFacts(saved) == 0 and materializedFacts(earlier) == 2
checkRun(earlier, 300)
assert materializedFacts(earlier) == 4
assert materializedOrdinal(earlier, CodeAddress(1200)) == 601
assert materializedOrdinal(earlier, CodeAddress(2800)) == 1401
checkRun(independent, 100)
assert materializedFacts(independent) == 2 and materializedFacts(earlier) == 4

# An interior-first entry still admits its complete containing block, including its original charge.
var interior = frame(plan, 900, true)
checkRun(interior, 900, true)
assert materializedFacts(interior) == 2

# Restoring a previously visited block reuses its facts despite out-of-source-order catalogue insertion.
saved = takeFlatStream(earlier)
var reused = frame(plan, 700)
restoreFlatStream(reused, saved)
checkRun(reused, 700)
assert materializedFacts(reused) == 4

# Full-source admission refuses an unreachable excess even though the first call needs only two facts.
var limits = defaultFlatLimits()
limits.facts = FlatFactLimit(2047)
assert prepareFlatPlan(source, GasCycleLimit(10000), limits, false).error ==
    FlatError.FactLimitExceeded
limits = defaultFlatLimits()
limits.nodes = FlatNodeLimit(1)
var boundedResult = prepareFlatPlan(source, GasCycleLimit(10000), limits, false)
assert boundedResult.error == FlatError.None
let bounded = takeValue(boundedResult)
var refused = frame(bounded, 700)
runFlat(refused, 2)
assert refused.reason == StepError.InvalidPreparedProgram
assert preparationError(refused) == FlatError.StreamLimitExceeded
assert flatNodes(refused) == 0 and materializedFacts(refused) == 2

# A valid cache cannot transfer derived metadata to an independently admitted plan identity.
saved = takeFlatStream(reused)
let other = newFlatPlan(source, GasCycleLimit(10000))
var foreign = frame(other, 700)
restoreFlatStream(foreign, saved)
assert preparationError(foreign) == FlatError.InvalidProgram
assert materializedFacts(foreign) == 0 and materializedFacts(saved) == 4

echo "PASS lazy admission / reached blocks / isolated catalogues / resource and identity boundaries"
