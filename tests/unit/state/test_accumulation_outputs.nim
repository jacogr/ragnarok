# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_outputs_arc_release"}

## Real terminal yields become immutable single-round output pairs and explicit history roots.

import std/[assertions, envvars, syncio]
import ../../../src/state/[accumulation_outputs, accumulation_execution, accumulation_inputs,
  accumulation_outcome, accumulation_batch, accumulation_round, history, store]
import ../../../src/codec/[bounded, report_owned, state_outputs, state_trie]
import ../../../src/crypto/primitives
import ../../support/[accumulation_execution_context, pvm_accumulation_context,
  pvm_accumulation_program, arc_evidence]

# Backend refusal proves preparation/query encoding is hash-free while explicit roots preserve typed failures.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}

# Authored bytecode alternatives exercise actual normalized selection instead of replacing contexts or outcomes.
type Ending = enum YieldHalt, YieldPanic, CheckpointPanic, ReturnOverride, ZeroReturn, UnreadableReturn

# Frame a complete service preimage with exact opcode masks; all guest bytes remain authored locally.
proc program(ending: Ending): seq[byte] =
  var instructions: seq[seq[byte]] = @[]
  if ending != ZeroReturn:
    instructions.add(registerImmediate(7, 65536))
    instructions.add(@[10'u8, 26]) # Yield the 32 readable RO bytes: 73 followed by zeros.
  case ending
  of YieldHalt:
    instructions.add(registerImmediate(8, 0)) # A non-32-byte halt preserves the regular yield.
  of YieldPanic:
    instructions.add(@[0'u8]) # No checkpoint retains the earlier regular yield.
  of CheckpointPanic:
    instructions.add(@[10'u8, 18])
    instructions.add(registerImmediate(7, 196608))
    instructions.add(@[10'u8, 26])
    instructions.add(@[0'u8]) # The later RW yield is discarded; checkpoint RO yield survives.
  of ReturnOverride:
    instructions.add(registerImmediate(7, 196608))
    instructions.add(registerImmediate(8, 32)) # Readable RW return overrides the previous RO yield.
  of ZeroReturn:
    instructions.add(registerImmediate(7, 65537))
    instructions.add(registerImmediate(8, 32)) # Padded RO bytes are readable and all zero, not absent.
  of UnreadableReturn:
    instructions.add(registerImmediate(7, high(uint64)))
    instructions.add(registerImmediate(8, 32)) # An unreadable return does not overwrite the earlier present yield.
  instructions.add(@[50'u8, 0])
  var code = @[0'u8, 0, 0, 0, 0]
  var starts = @[0, 1, 2, 3, 4]
  for instruction in instructions:
    starts.add(code.len)
    for octet in instruction: code.add(octet) # Immediates are never marked as opcodes.
  assert code.len < 128
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for index in starts: mask[index div 8] = mask[index div 8] or byte(1 shl (index mod 8))
  for octet in mask: raw.add(octet)
  result = @[0'u8] # Complete code preimage begins with empty metadata framing.
  for octet in pvmEnvelope(raw): result.add(octet)

# Independent fixed commitment expectations distinguish real zero values from absence.
proc commitment(first: byte): array[32, byte] =
  result = default(array[32, byte])
  result[0] = first

# Bound source traversal, output cardinality and complete wire bytes independently.
proc policy(executions = 2'u64, items = 2'u64, bytes = 73'u64): AccumulationOutputLimits =
  AccumulationOutputLimits(executions: ElementLimit(executions),
    log: OutputLogConfig(items: ElementLimit(items), maxBytes: ByteLimit(bytes)))

# Literal E4-service/hash leaf framing, independent of the production log/root encoders.
proc leaf(service: uint32, first: byte): seq[byte] =
  result = @[]
  for shift in 0..<4: result.add(byte((service shr (shift*8)) and 255))
  for index in 0..<32: result.add(if index == 0: first else: 0'u8)

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let fixture = executionFixture(base, firstProgram = program(YieldHalt), secondProgram = program(ReturnOverride))
  let first = executionGuest(fixture, 0)
  let second = executionGuest(fixture, 1)
  let completed = completeBlockAccumulation(fixture.round, [second, first], [], executionLimits()).value
  failHash(3)
  let plan = prepareAccumulationOutputs(completed, policy()).value
  let info = plan.outputsInfo.value
  assert info.outputs == 2 and info.encodedBytes == 73
  let a = plan.outputAt(OutputLogIndex(0)).value
  let b = plan.outputAt(OutputLogIndex(1)).value
  assert uint32(a.service) == 42 and array[32, byte](a.commitment) == commitment(73)
  assert uint32(b.service) == 99 and array[32, byte](b.commitment) == commitment(81)
  var expectedWire = @[2'u8]
  for octet in leaf(42, 73): expectedWire.add(octet)
  for octet in leaf(99, 81): expectedWire.add(octet)
  var entry = plan.outputsEntry.value
  assert entry.value == expectedWire
  entry.value[0] = 9
  var copied = plan.outputAt(OutputLogIndex(0)).value
  copied.commitment = OutputCommitment(commitment(7))
  assert plan.outputsEntry.value.value == expectedWire # Fresh encoding cannot expose the retained row storage.
  assert array[32, byte](plan.outputAt(OutputLogIndex(0)).value.commitment) == commitment(73)
  assert uint64(plan.outputsSource.value.executionInfo.value.gasUsed) == uint64(
      completed.executionInfo.value.gasUsed)
  assert sameAccumulationInputs(plan.outputsSource.value.executionRound.value.roundProjection.value.roundInputs.value,
    completed.executionRound.value.roundProjection.value.roundInputs.value)
  let refusedRoot = plan.outputsRoot
  assert refusedRoot.historyError == HistoryTransitionError.BackendFailure
  assert plan.outputsInfo.value.outputs == 2 # Failed explicit hashing does not invalidate the retained source or pairs.
  assert plan.outputAt(OutputLogIndex(high(uint64))).error == AccumulationOutputsError.InvalidIndex
  assert prepareAccumulationOutputs(completed, policy(executions = 1)).error ==
      AccumulationOutputsError.LimitExceeded
  assert prepareAccumulationOutputs(completed, policy(items = 1)).error ==
      AccumulationOutputsError.LimitExceeded
  assert prepareAccumulationOutputs(completed, policy(bytes = 72)).error ==
      AccumulationOutputsError.LimitExceeded
  failHash(0)
  var node = @[110'u8, 111, 100, 101] # Literal ASCII node domain, then raw ordered 36-byte leaves.
  for octet in leaf(42, 73): node.add(octet)
  for octet in leaf(99, 81): node.add(octet)
  let expectedRoot = array[32, byte](keccak256(node).value)
  assert array[32, byte](plan.outputsRoot.value) == expectedRoot
  let originalOrder = completeBlockAccumulation(fixture.round, [first, second], [], executionLimits()).value
  let ordered = prepareAccumulationOutputs(originalOrder, policy()).value
  assert ordered.outputsEntry.value.value == expectedWire
  assert array[32, byte](ordered.outputsRoot.value) == expectedRoot
  for ending in [YieldPanic, CheckpointPanic, ZeroReturn, UnreadableReturn]:
    # A non-executing peer contributes no pair; one selected presence distinguishes all terminal alternatives.
    let source = executionFixture(base, second = ExecutionEnding.Missing, firstProgram = program(ending))
    let result = completeBlockAccumulation(source.round, [executionGuest(source, 0)], [
        executionSkip(source, 1)], executionLimits()).value
    failHash(3)
    let outputs = prepareAccumulationOutputs(result, policy(executions = 1, items = 1,
        bytes = 37)).value
    if ending == YieldPanic:
      assert outputs.outputsInfo.value.outputs == 0
      assert outputs.outputsEntry.value.value == @[0'u8]
      assert array[32, byte](outputs.outputsRoot.value) == default(array[32,
          byte]) # Empty root requires no backend.
    else:
      assert outputs.outputsInfo.value.outputs == 1
      let expected = if ending == ZeroReturn: 0'u8 else: 73'u8
      assert array[32, byte](outputs.outputAt(OutputLogIndex(0)).value.commitment) == commitment(expected)
      failHash(0)
      assert array[32, byte](outputs.outputsRoot.value) == array[32, byte](keccak256(leaf(42,
          expected)).value)
    failHash(0)
  let duplicate = executionFixture(base, firstProgram = program(YieldHalt), secondProgram = program(YieldHalt))
  let duplicateSource = completeBlockAccumulation(duplicate.round,
    [executionGuest(duplicate, 1), executionGuest(duplicate, 0)], [], executionLimits()).value
  let duplicateOutputs = prepareAccumulationOutputs(duplicateSource, policy()).value
  assert duplicateOutputs.outputsInfo.value.outputs ==
      2 # Identical hashes on different services are distinct pairs.
  assert array[32, byte](duplicateOutputs.outputAt(OutputLogIndex(1)).value.commitment) ==
      commitment(73)
  let noYield = executionFixture(base)
  let noYieldSource = completeBlockAccumulation(noYield.round,
    [executionGuest(noYield, 0), executionGuest(noYield, 1)], [], executionLimits()).value
  failHash(3)
  assert prepareAccumulationOutputs(noYieldSource, policy(items = 0,
      bytes = 1)).value.outputsInfo.value.outputs == 0
  assert prepareAccumulationOutputs(noYieldSource, policy(executions = 1, items = 0,
      bytes = 1)).error == AccumulationOutputsError.LimitExceeded
  assert prepareAccumulationOutputs(noYieldSource, policy(items = 0, bytes = 0)).error ==
      AccumulationOutputsError.LimitExceeded
  let defaultSource = default(CompletedBlockAccumulation)
  assert prepareAccumulationOutputs(defaultSource, policy()).error ==
      AccumulationOutputsError.InvalidSource
  let defaultPlan = default(PreparedAccumulationOutputs)
  assert defaultPlan.outputsInfo.error == AccumulationOutputsError.Uninitialized
  assert defaultPlan.outputsSource.error == AccumulationOutputsError.Uninitialized
  assert defaultPlan.outputAt(OutputLogIndex(0)).error == AccumulationOutputsError.Uninitialized
  assert defaultPlan.outputsEntry.error == AccumulationOutputsError.Uninitialized
  assert defaultPlan.outputsRoot.error == AccumulationOutputsError.Uninitialized
  let defaultResult = default(AccumulationOutputsResult[PreparedAccumulationOutputs])
  assert defaultResult.error == AccumulationOutputsError.Uninitialized
  failHash(0)
  let allSkip = executionFixture(base, first = ExecutionEnding.Missing,
      second = ExecutionEnding.Missing)
  let allSkipSource = completeBlockAccumulation(allSkip.round, [],
    [executionSkip(allSkip, 0), executionSkip(allSkip, 1)], executionLimits()).value
  let empty = executionFixture(base, empty = true)
  let emptySource = completeBlockAccumulation(empty.round, [], [], executionLimits(0)).value
  failHash(3)
  for source in [allSkipSource, emptySource]:
    let outputs = prepareAccumulationOutputs(source, policy(executions = 0, items = 0,
        bytes = 1)).value
    assert outputs.outputsInfo.value.outputs == 0
    assert outputs.outputsEntry.value.value == @[0'u8]
    assert array[32, byte](outputs.outputsRoot.value) == default(array[32, byte])
  failHash(0)
  var retained: PreparedAccumulationOutputs
  block:
    let local = executionFixture(base, firstProgram = program(YieldHalt), secondProgram = program(ReturnOverride))
    let source = completeBlockAccumulation(local.round,
      [executionGuest(local, 0), executionGuest(local, 1)], [], executionLimits()).value
    retained = prepareAccumulationOutputs(source, policy()).value
  assert retained.outputsEntry.value.value == expectedWire
  assert array[32, byte](retained.outputsRoot.value) == expectedRoot
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Private pair arrays, encoded copies and refused/complete roots release with their retained source handles.
    let outputs = prepareAccumulationOutputs(completed, policy()).value
    assert outputs.outputsEntry.value.value == expectedWire
    failHash(2)
    assert outputs.outputsRoot.historyError == HistoryTransitionError.BackendFailure
    failHash(0)
    assert array[32, byte](outputs.outputsRoot.value) == expectedRoot
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_outputs", 1000, before, after)
  echo "Accumulation round outputs passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # I/O and unexpected exceptions remain unsuccessful native executions.
except:
  quit(2)
