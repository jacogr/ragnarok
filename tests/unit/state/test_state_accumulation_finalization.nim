# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_finalization_arc_release"}

## Genuine stopped accseq histories retain service effects and privately replace only the output chapter.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/state/accumulation_outputs as state_accumulation_outputs
import ../../../src/state/accumulation_reentry as state_accumulation_reentry
import ../../../src/state/accumulation_continuation_execution as state_accumulation_continuation_execution
import ../../../src/state/accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ../../../src/state/accumulation_continuation as state_accumulation_continuation
import ../../../src/state/accumulation_execution as state_accumulation_execution
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/accumulation_skip as state_accumulation_skip
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_outputs as codec_state_outputs
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../support/state_accumulation_reentry_context
import ../../support/state_accumulation_execution_context
import ../../support/pvm_accumulation_context
import ../../support/pvm_accumulation_provision
import ../../support/state_report_context
import ../../support/testing_arc_evidence

# Fail only after genuine signed execution and stopped-source preparation have completed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Yield the actual 32-byte padded bootstrap tuple, then halt without overriding it.
proc yieldArguments(): seq[byte] =
  result = @[0'u8]
  let raw = @[0'u8, 0, 9, 0, 0, 0, 0, 0, 10, 27, 50, 0, 191, 0]
  for octet in pvmEnvelope(raw): result.add(octet) # Independent literal opcode mask marks host and halt starts.

# Complete both fixture services through the existing real guest dispatcher; an idle source has neither.
proc completed(source: PreparedAccumulationReentry,
    provided = false): CompletedAccumulationReentry =
  var runs: seq[AccumulationDispatchResult] = @[]
  for index in 0..<source.reentryInputs.value.invocationServiceCount.value:
    runs.add(reentryGuest(source, uint64(index), provided = provided and index == 0))
  completeAccumulationReentry(source, runs, [], executionLimits()).value

# Keep selection/materialization local to each advance; the separate history collector bounds all retained rounds.
proc config(): AccumulationReentryConfig =
  AccumulationReentryConfig(selection: AccumulationContinuationLimits(executions: ElementLimit(2),
    reports: ElementLimit(4), digests: ElementLimit(8)), operands: executionRoundConfig().operands,
    inputs: executionRoundConfig().inputs)

# Exact four-round traversal and independent final union limits for the authored repeated-entry fixture.
proc policy(rounds = 4'u64, executions = 6'u64, items = 4'u64,
    bytes = 145'u64): AccumulationOutputHistoryLimits =
  AccumulationOutputHistoryLimits(rounds: ElementLimit(rounds), executions: ElementLimit(
      executions),
    log: OutputLogConfig(items: ElementLimit(items), maxBytes: ByteLimit(bytes)))

# Literal E4-service and opaque 32-byte commitment framing, independent of the production log codec.
proc expectedLog(): seq[byte] =
  result = @[4'u8]
  for service in [42'u32, 99]:
    for count in (if service == 42: [1'u8, 2] else: [0'u8, 1]):
      for shift in 0..<4: result.add(byte((service shr (shift*8)) and 255))
      result.add(2)
      result.add(byte(service))
      result.add(count)
      for index in 3..<32: result.add(0) # Compact slot/service/count arguments occupy three bytes.

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  let code = yieldArguments()
  let key = chapterKey(StateChapter(16))
  let fixture = reentryFixture(base, firstProgram = code, secondProgram = code,
    extra = @[StateEntry(key: key, value: @[0'u8])])
  let running = completed(fixture.source)
  let firstContinuation = fixture.source.reentrySource.value
  failHash(3)
  assert prepareFinalAccumulation(running, policy()).error ==
      AccumulationFinalizationError.NotStopped
  assert prepareFinalAccumulation(firstContinuation, policy()).error ==
      AccumulationFinalizationError.NotStopped
  assert prepareFinalAccumulation(default(CompletedAccumulationReentry), policy()).error ==
      AccumulationFinalizationError.InvalidSource
  assert prepareFinalAccumulation(default(CompletedAccumulationContinuation), policy()).error ==
      AccumulationFinalizationError.InvalidSource
  assert hashCalls() == 0 # Refused live/default sources do not collect, encode or hash a candidate.
  let terminal = prepareAccumulationReentry(running, config(), AccumulationReentryDepthLimit(2)).value
  assert not terminal.reentryInfo.value.dispatch
  failHash(0)
  let terminalDone = completed(terminal)
  let prior = terminal.reentryState.value
  assert prior.lookup(key).value.bytes == @[0'u8]
  failHash(3)
  let refused = prepareFinalAccumulation(terminalDone, policy())
  assert refused.error == AccumulationFinalizationError.StateFailure
  assert refused.stateError == StateStoreError.BackendFailure
  assert sameStateSnapshot(prior, terminal.reentryState.value)
  assert prior.lookup(key).value.bytes == @[0'u8]
  for limit in [policy(rounds = 3), policy(executions = 5), policy(items = 3), policy(bytes = 144)]:
    let refused = prepareFinalAccumulation(terminalDone, limit)
    assert refused.error == AccumulationFinalizationError.OutputFailure
    assert refused.outputError == AccumulationOutputsError.LimitExceeded
  failHash(0)
  let expected = expectedLog()
  var rows: seq[StateEntry] = @[]
  for entry in fixture.initial.entries:
    # Replace only the literal old C(16), independently of the production candidate's encoded bytes.
    let value = if array[31, byte](entry.key) == array[31, byte](key): expected else: entry.value
    rows.add(StateEntry(key: entry.key, value: value))
  let expectedState = newStateStore(rows, state_report_context.limits()).value.snapshot.value
  let final = prepareFinalAccumulation(terminalDone, policy()).value
  let info = final.finalAccumulationInfo.value
  assert uint64(info.completedPrefix) == 4 and info.pendingReports == 0
  assert uint64(info.remainingGas) == uint64(terminal.reentryInfo.value.budget)
  assert info.outputs.rounds == 4 and info.outputs.executions == 6
  assert info.outputs.outputs == 4 and info.outputs.encodedBytes == 145
  let candidate = final.finalAccumulationState.value
  assert candidate.lookup(key).value.bytes == expected
  assert array[32, byte](candidate.commitment.root) == array[32, byte](
      expectedState.commitment.root)
  for entry in fixture.initial.entries:
    if array[31, byte](entry.key) != array[31, byte](key):
      assert candidate.lookup(entry.key).value.bytes ==
          entry.value # Every unrelated chapter/account entry survives unchanged.
  assert not sameStateSnapshot(candidate, prior)
  assert sameStateSnapshot(fixture.initial.state.snapshot.value, prior)
  let retained = final.finalAccumulationOutputs.value
  assert sameAccumulationInputs(retained.outputsReentry.value.executionReentry.value.reentryInputs.value,
    terminal.reentryInputs.value)
  assert retained.outputsEntry.value.value == expected
  var observed = info
  observed.pendingReports = high(int)
  assert final.finalAccumulationInfo.value.pendingReports == 0
  let again = prepareFinalAccumulation(terminalDone, policy()).value
  assert array[32, byte](again.finalAccumulationState.value.commitment.root) == array[32, byte](
      candidate.commitment.root)
  assert terminal.reentryState.value.lookup(key).value.bytes == @[0'u8]
  let empty = default(PreparedFinalAccumulation)
  assert empty.finalAccumulationInfo.error == AccumulationFinalizationError.Uninitialized
  assert empty.finalAccumulationOutputs.error == AccumulationFinalizationError.Uninitialized
  assert empty.finalAccumulationState.error == AccumulationFinalizationError.Uninitialized
  let emptyFixture = reentryFixture(base, empty = true)
  let stoppedFixture = reentryFixture(base, stopped = true)
  for source in [emptyFixture.source.reentrySource.value,
      stoppedFixture.source.reentrySource.value]:
    # A stopped first continuation may have no reports, or retain the unaffordable original suffix.
    assert not source.executionInfo.value.round.dispatch
    let final = prepareFinalAccumulation(source, policy(rounds = 2, executions = 2,
      items = 0, bytes = 1)).value
    let info = final.finalAccumulationInfo.value
    let round = source.executionInfo.value.round
    assert uint64(info.completedPrefix) == uint64(round.completedPrefix)
    assert info.pendingReports == round.pendingReports
    assert uint64(info.remainingGas) == uint64(round.budget)
    assert final.finalAccumulationState.value.lookup(key).value.bytes == @[0'u8]
    assert source.executionContinuation.value.continuationState.value.lookup(key).error ==
        StateStoreError.MissingKey
  for source in [emptyFixture.source, stoppedFixture.source]:
    # Both terminal representations preserve the exact pending suffix, including a nonempty unaffordable head.
    let final = prepareFinalAccumulation(completed(source), policy(rounds = 3, executions = 2,
      items = 0, bytes = 1)).value
    assert final.finalAccumulationInfo.value.pendingReports ==
        source.reentryInfo.value.pendingReports
    assert final.finalAccumulationState.value.lookup(key).value.bytes == @[0'u8]
  let pending = prepareFinalAccumulation(stoppedFixture.source.reentrySource.value, policy()).value
  assert pending.finalAccumulationInfo.value.pendingReports == 3
  let provided = reentryFixture(base, provided = true)
  let providedDone = completed(provided.source, provided = true)
  let providedTerminal = prepareAccumulationReentry(providedDone, config(),
      AccumulationReentryDepthLimit(2)).value
  let providedFinal = prepareFinalAccumulation(completed(providedTerminal), policy()).value
  let request = provisionRequest(42, @[73'u8])
  assert providedFinal.finalAccumulationState.value.lookup(request.key).value.bytes == @[1'u8, 2, 0, 0, 0]
  assert provided.initial.state.snapshot.value.lookup(request.key).value.bytes == @[0'u8]
  assert sameStateSnapshot(provided.source.reentryState.value, providedTerminal.reentryState.value)
  assert providedFinal.finalAccumulationState.value.lookup(key).value.bytes == @[0'u8]
  var detached: PreparedFinalAccumulation
  block:
    let local = reentryFixture(base, firstProgram = code, secondProgram = code)
    let terminal = prepareAccumulationReentry(completed(local.source), config(),
        AccumulationReentryDepthLimit(2)).value
    detached = prepareFinalAccumulation(completed(terminal), policy()).value
  assert detached.finalAccumulationState.value.lookup(key).value.bytes == expected
  assert detached.finalAccumulationOutputs.value.outputsReentry.value.executionInfo.value.round.dispatch == false
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Complete private maps, output arrays and refused scratch release while retained sources remain usable.
    failHash(1)
    assert prepareFinalAccumulation(terminalDone, policy()).stateError ==
        StateStoreError.BackendFailure
    failHash(0)
    let final = prepareFinalAccumulation(terminalDone, policy()).value
    assert final.finalAccumulationState.value.lookup(key).value.bytes == expected
    assert array[32, byte](final.finalAccumulationState.value.commitment.root) == array[32, byte](
        candidate.commitment.root)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_accumulation_finalization", 1000, before, after)
  echo "Final accumulation candidate passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Unexpected exceptions and fixture I/O errors remain native failures.
except:
  quit(2)
