# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_reentry_outputs_arc_release"}

## Genuine repeated rounds form a bounded immutable pair union, with independent literal log/root witnesses.

import std/[assertions, envvars, syncio]
import ../../../src/state/accumulation/[outputs as accumulation_outputs,
    execution as accumulation_execution]
import ../../../src/state/accumulation/continuation/[
    execution as accumulation_continuation_execution, inputs as accumulation_continuation_inputs]
import ../../../src/state/accumulation/[continuation as accumulation_continuation,
    reentry as accumulation_reentry, inputs as accumulation_inputs,
    dispatch as accumulation_dispatch, skip as accumulation_skip, service as accumulation_service]
import ../../../src/state/[history, store]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/[outputs as state_outputs, trie as state_trie]
import ../../../src/crypto/primitives
import ../../support/[accumulation_reentry_context, accumulation_execution_context,
  accumulation_continuation_execution_context, pvm_accumulation_context,
  pvm_accumulation_program, arc_evidence]

# Fail hashing only after genuine signed sources have been constructed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Return the real compact bootstrap tuple, or a fixed readable address, from the initialized CPU.
proc returnProgram(address = 0'u64): seq[byte] =
  var instructions: seq[seq[byte]] = @[]
  if address != 0:
    instructions.add(registerImmediate(7, address)) # Fixed-page mode supplies equal or zero commitments.
  instructions.add(registerImmediate(8, 32))
  instructions.add(@[50'u8, 0])
  var code = @[0'u8, 0, 0, 0, 0]
  var starts = @[0, 1, 2, 3, 4]
  for instruction in instructions:
    starts.add(code.len)
    for octet in instruction: code.add(octet) # Argument data is never marked as an instruction.
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var mask = newSeq[byte]((code.len+7) div 8)
  for index in starts:
    mask[index div 8] = mask[index div 8] or byte(1 shl (index mod 8))
  for octet in mask: raw.add(octet)
  result = @[0'u8]
  for octet in pvmEnvelope(raw): result.add(octet)

# Complete through genuine guests/skips, never synthetic terminal observations.
proc completed(source: PreparedAccumulationReentry): CompletedAccumulationReentry =
  var runs: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  let count = source.reentryInputs.value.invocationServiceCount.value
  for index in 0..<count:
    let service = prepareReentryAccumulationService(source, InvocationServiceIndex(uint64(index)),
      continuationServiceConfig()).value
    if service.serviceInfo.value.code == AccumulationCodeStatus.Ready:
      runs.add(reentryGuest(source, uint64(index))) # Execute in reverse collection order to remove arrival-order dependence.
    else:
      skips.add(finishUninvokedAccumulation(service).value) # Missing preimages are certified rather than fabricated.
  if runs.len == 2:
    let first = runs[0]
    let second = runs[1]
    runs[0] = second
    runs[1] = first
  completeAccumulationReentry(source, runs, skips, executionLimits(uint64(count))).value

# Advance only genuine source-selected report ranges under the existing bounded materialization contract.
proc config(): AccumulationReentryConfig =
  AccumulationReentryConfig(selection: AccumulationContinuationLimits(executions: ElementLimit(2),
    reports: ElementLimit(4), digests: ElementLimit(8)), operands: executionRoundConfig().operands,
    inputs: executionRoundConfig().inputs)

# Traversal counts include initial/first continuation and outcomes with duplicate or absent yields.
proc policy(rounds = 6'u64, executions = 10'u64, items = 4'u64,
    bytes = 145'u64): AccumulationOutputHistoryLimits =
  AccumulationOutputHistoryLimits(rounds: ElementLimit(rounds), executions: ElementLimit(
      executions),
    log: OutputLogConfig(items: ElementLimit(items), maxBytes: ByteLimit(bytes)))

# Independent fixed leaves encode E4 service and raw argument bytes without using the production codec.
proc leaf(service: uint32, count: byte): seq[byte] =
  result = @[]
  for shift in 0..<4: result.add(byte((service shr (shift*8)) and 255))
  result.add(2)
  result.add(byte(service))
  result.add(count)
  for index in 3..<32: result.add(0) # All three compact arguments fit one byte in this fixture.

# Build an independent binary node transcript for exactly two raw leaves or two hashed children.
proc node(left, right: seq[byte]): seq[byte] =
  var bytes = @[110'u8, 111, 100, 101]
  for octet in left: bytes.add(octet)
  for octet in right: bytes.add(octet)
  result = @[]
  for octet in array[32, byte](keccak256(bytes).value): result.add(octet)

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let tail = @[reentryReady(base, 68, [100000'u64, 100000]),
    reentryReady(base, 69, [100000'u64, 100000]), reentryReady(base, 70, [0'u64])]
  let program = returnProgram()
  let fixture = reentryFixture(base, firstGas = 100000, secondGas = 100000, tail = tail,
    firstProgram = program, secondProgram = program)
  let firstDone = completed(fixture.source)
  let second = prepareAccumulationReentry(firstDone, config(), AccumulationReentryDepthLimit(4)).value
  let secondDone = completed(second)
  let third = prepareAccumulationReentry(secondDone, config(), AccumulationReentryDepthLimit(4)).value
  let thirdDone = completed(third)
  let terminal = prepareAccumulationReentry(thirdDone, config(), AccumulationReentryDepthLimit(4)).value
  assert not terminal.reentryInfo.value.dispatch
  let terminalDone = completed(terminal)
  let continuation = fixture.source.reentrySource.value
  let initial = continuation.executionContinuation.value.continuationPlan.value.continuationSource.value
  var expectedWire = @[4'u8]
  for pair in [leaf(42, 1), leaf(42, 2), leaf(99, 0), leaf(99, 1)]:
    for octet in pair: expectedWire.add(octet) # Same-service distinct commitments are ordered by all hash octets.
  let expectedRoot = node(node(leaf(42, 1), leaf(42, 2)), node(leaf(99, 0), leaf(99, 1)))
  failHash(3)
  let outputs = prepareAccumulationOutputs(terminalDone, policy()).value
  let info = outputs.outputsInfo.value
  assert info.rounds == 6 and info.executions == 10
  assert info.outputs == 4 and info.encodedBytes == 145
  assert outputs.outputsEntry.value.value == expectedWire
  assert hashCalls() == 0 # Neither iterative traversal, pair sorting nor encoding hashes.
  assert outputs.outputsRoot.historyError == HistoryTransitionError.BackendFailure
  assert sameAccumulationInputs(outputs.outputsSource.value.executionRound.value.roundProjection.value.roundInputs.value,
    initial.executionRound.value.roundProjection.value.roundInputs.value)
  assert sameAccumulationInputs(outputs.outputsContinuation.value.executionContinuation.value.continuationInputs.value,
    continuation.executionContinuation.value.continuationInputs.value)
  assert sameAccumulationInputs(outputs.outputsReentry.value.executionReentry.value.reentryInputs.value,
    terminal.reentryInputs.value)
  assert sameStateSnapshot(fixture.initial.state.snapshot.value, fixture.source.reentryState.value)
  for limit in [policy(rounds = 5), policy(executions = 9), policy(items = 3), policy(bytes = 144),
      policy(rounds = 0), policy(executions = 0), policy(items = 0), policy(bytes = 0)]:
    assert prepareAccumulationOutputs(terminalDone, limit).error ==
        AccumulationOutputsError.LimitExceeded
  let wide = policy(rounds = high(uint64), executions = high(uint64), items = high(uint64),
      bytes = high(uint64))
  assert prepareAccumulationOutputs(terminalDone, wide).value.outputsEntry.value.value == expectedWire
  let partial = prepareAccumulationOutputs(firstDone, policy(rounds = 3, executions = 6)).value
  assert partial.outputsEntry.value.value == expectedWire # Later identical pairs consume work but not extra log cardinality.
  let later = prepareAccumulationOutputs(continuation, policy(rounds = 2, executions = 4)).value
  assert later.outputsInfo.value.outputs == 3
  assert later.outputsInfo.value.rounds == 2
  assert later.outputsReentry.error == AccumulationOutputsError.NoReentry
  assert prepareAccumulationOutputs(continuation, policy(rounds = 1)).error ==
      AccumulationOutputsError.LimitExceeded
  assert prepareAccumulationOutputs(continuation, policy(executions = 3)).error ==
      AccumulationOutputsError.LimitExceeded
  let first = prepareAccumulationOutputs(initial, AccumulationOutputLimits(executions: ElementLimit(2),
    log: OutputLogConfig(items: ElementLimit(2), maxBytes: ByteLimit(73)))).value
  assert first.outputsInfo.value.rounds == 1 and first.outputsInfo.value.executions == 2
  assert first.outputsContinuation.error == AccumulationOutputsError.NoContinuation
  assert first.outputsReentry.error == AccumulationOutputsError.NoReentry
  var copied = outputs.outputAt(OutputLogIndex(0)).value
  copied.commitment = OutputCommitment(default(array[32, byte]))
  var entry = outputs.outputsEntry.value
  entry.value[0] = 0
  assert outputs.outputsEntry.value.value == expectedWire # Neither records nor encoded bytes alias the owner.
  assert outputs.outputAt(OutputLogIndex(high(uint64))).error ==
      AccumulationOutputsError.InvalidIndex
  let empty = default(PreparedAccumulationOutputs)
  assert empty.outputsContinuation.error == AccumulationOutputsError.Uninitialized
  assert empty.outputsReentry.error == AccumulationOutputsError.Uninitialized
  assert prepareAccumulationOutputs(default(CompletedAccumulationReentry), policy()).error ==
      AccumulationOutputsError.InvalidSource
  assert prepareAccumulationOutputs(default(CompletedAccumulationContinuation), policy()).error ==
      AccumulationOutputsError.InvalidSource
  failHash(0)
  let root = array[32, byte](outputs.outputsRoot.value)
  for index in 0..<32: assert root[index] == expectedRoot[index]
  let absentFixture = reentryFixture(base)
  let skippedFixture = reentryFixture(base, first = ExecutionEnding.Missing,
      second = ExecutionEnding.Missing)
  let absent = completed(absentFixture.source)
  let skipped = completed(skippedFixture.source)
  failHash(3)
  for source in [absent, skipped]:
    let plan = prepareAccumulationOutputs(source, policy(rounds = 3, executions = 6, items = 0,
        bytes = 1)).value
    assert plan.outputsInfo.value.outputs == 0
    assert plan.outputsEntry.value.value == @[0'u8]
    assert array[32, byte](plan.outputsRoot.value) == default(array[32, byte])
    assert prepareAccumulationOutputs(source, policy(bytes = 0)).error ==
        AccumulationOutputsError.LimitExceeded
  assert prepareAccumulationOutputs(absent, policy(executions = 5)).error ==
      AccumulationOutputsError.LimitExceeded
  assert prepareAccumulationOutputs(skipped, policy(executions = 0, items = 0,
      bytes = 1)).value.outputsInfo.value.executions == 0
  failHash(0)
  for address in [65536'u64, 65537]:
    # Identical commitments on different services stay distinct; present zero remains a genuine pair.
    let code = returnProgram(address)
    let local = reentryFixture(base, firstProgram = code, secondProgram = code)
    let source = completed(local.source)
    failHash(3)
    let outputs = prepareAccumulationOutputs(source, policy(rounds = 3, executions = 6,
      items = 2, bytes = 73)).value
    assert outputs.outputsInfo.value.outputs == 2
    let a = outputs.outputAt(OutputLogIndex(0)).value
    let b = outputs.outputAt(OutputLogIndex(1)).value
    assert uint32(a.service) == 42 and uint32(b.service) == 99
    assert array[32, byte](a.commitment) == array[32, byte](b.commitment)
    let expected = if address == 65536: 73'u8 else: 0'u8
    let commitment = array[32, byte](a.commitment)
    assert commitment[0] == expected
    for index in 1..<32: assert commitment[index] == 0
    assert outputs.outputsEntry.value.value.len == 73
    failHash(0)
  var retained: PreparedAccumulationOutputs
  block:
    let local = reentryFixture(base, firstProgram = program, secondProgram = program)
    retained = prepareAccumulationOutputs(completed(local.source), policy()).value
  assert retained.outputsEntry.value.value == expectedWire # The output owner retains the whole genuine chain after local handles expire.
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let plan = prepareAccumulationOutputs(terminalDone, policy()).value
    assert plan.outputsEntry.value.value == expectedWire
    failHash(2)
    assert plan.outputsRoot.historyError == HistoryTransitionError.BackendFailure
    failHash(0)
    let root = array[32, byte](plan.outputsRoot.value)
    for index in 0..<32: assert root[index] == expectedRoot[index]
    assert prepareAccumulationOutputs(terminalDone, policy(rounds = 5)).error ==
        AccumulationOutputsError.LimitExceeded
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_reentry_outputs", 1000, before, after)
  echo "Accumulation history outputs passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # I/O and unexpected exceptions remain strict native failures.
except:
  quit(2)
