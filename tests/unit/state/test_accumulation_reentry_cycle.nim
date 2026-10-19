# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_reentry_cycle_arc_release"}

## Reuse the same genuine prepared/completed types through bounded repeated report-only accseq entries.

import std/[assertions, envvars, syncio]
import ../../../src/state/[accumulation_reentry, accumulation_reentry_execution,
  accumulation_reentry_invocation, accumulation_continuation_execution,
  accumulation_continuation_inputs,
  accumulation_execution, accumulation_inputs, accumulation_operands, accumulation_continuation,
  accumulation_service, accumulation_invocation, accumulation_dispatch, accumulation_skip,
  accumulation_batch, store]
import ../../../src/codec/[bounded, report_owned, work_digest, state_trie]
import ../../support/[accumulation_reentry_context, accumulation_continuation_execution_context,
  accumulation_execution_context, accumulation_transfer_reentry, arc_evidence]

# Verify shared selection/materialization/application performs no hidden hashes for no-op batches.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Complete every actual input through real dispatch or the genuine non-invoking code gate.
proc completed(source: PreparedAccumulationReentry): CompletedAccumulationReentry =
  var runs: seq[AccumulationDispatchResult] = @[]
  var skips: seq[SkippedAccumulation] = @[]
  let count = source.reentryInputs.value.invocationServiceCount.value
  for index in 0..<count:
    let service = prepareReentryAccumulationService(source, InvocationServiceIndex(uint64(index)),
      continuationServiceConfig()).value
    if service.serviceInfo.value.code == AccumulationCodeStatus.Ready:
      runs.add(reentryGuest(source, uint64(index))) # Actual CPU outcomes supply gas; none is caller-authored.
    else:
      skips.add(finishUninvokedAccumulation(service).value) # Only certified code-unavailable alternatives skip.
  completeAccumulationReentry(source, runs, skips, executionLimits(uint64(count))).value

# Independent work/materialization caps apply to just the next entry, while depth is an explicit separate argument.
proc config(): AccumulationReentryConfig =
  AccumulationReentryConfig(selection: AccumulationContinuationLimits(executions: ElementLimit(2),
    reports: ElementLimit(4), digests: ElementLimit(8)), operands: executionRoundConfig().operands,
    inputs: executionRoundConfig().inputs)

proc main() {.raises.} =
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index in 0..<raw.len: bytes[index] = byte(raw[
      index]) # Preserve checksum-verified transport before genuine signing.
  let base = decodeOwnedReport(bytes, 2).value
  checkTransferReentry(base) # Genuine transfer-only cycles preserve gas, credit and source/depth ownership.
  let tail = @[reentryReady(base, 68, [100000'u64, 100000]),
    reentryReady(base, 69, [100000'u64, 100000]), reentryReady(base, 70, [0'u64])]
  let fixture = reentryFixture(base, firstGas = 100000, secondGas = 100000, tail = tail)
  let first = fixture.source
  let cap = AccumulationReentryDepthLimit(4)
  assert uint64(first.reentryInfo.value.depth) == 1
  assert first.reentryPrevious.error == AccumulationReentryError.NoPrevious
  let firstDone = completed(first)
  failHash(3)
  let second = prepareAccumulationReentry(firstDone, config(), cap).value
  assert uint64(second.reentryInfo.value.depth) == 2
  assert uint64(second.reentryInfo.value.completedPrefix) == 4
  assert uint64(second.reentryInfo.value.prefix) == 1
  assert uint64(second.reentryInfo.value.budget) == 200868
  assert sameAccumulationInputs(second.reentryPrevious.value.executionReentry.value.reentryInputs.value,
    first.reentryInputs.value)
  assert sameAccumulationInputs(second.reentrySource.value.executionContinuation.value.continuationInputs.value,
    first.reentrySource.value.executionContinuation.value.continuationInputs.value)
  assert sameStateSnapshot(second.reentryState.value, first.reentryState.value)
  let operands = second.reentryInputs.value.invocationOperands.value
  assert uint64(operands.operandReportStart.value) == 4
  assert uint64(operands.operandReportPrefix.value) == 1
  let report = second.reentryReportAt(ContinuationReportIndex(0)).value
  assert ownedReportInfo(report).value.header.packageHash.bytes[0] == 68
  let shortDepth = prepareAccumulationReentry(firstDone, config(), AccumulationReentryDepthLimit(1))
  assert shortDepth.error == AccumulationReentryError.LimitExceeded
  let wide = prepareAccumulationReentry(firstDone, config(), AccumulationReentryDepthLimit(high(uint64))).value
  assert uint64(wide.reentryInfo.value.depth) == 2 # Full-width policy never becomes an allocation size or unchecked increment.
  let zero = prepareAccumulationReentry(firstDone, config(), AccumulationReentryDepthLimit(0))
  assert zero.error == AccumulationReentryError.LimitExceeded
  var limited = config()
  limited.selection.reports = ElementLimit(0)
  assert prepareAccumulationReentry(firstDone, limited, cap).error ==
      AccumulationReentryError.LimitExceeded
  limited = config()
  limited.operands.reports = ElementLimit(0)
  assert prepareAccumulationReentry(firstDone, limited, cap).operandError ==
      AccumulationOperandError.LimitExceeded
  limited = config()
  limited.inputs.services = ElementLimit(0)
  assert prepareAccumulationReentry(firstDone, limited, cap).inputError ==
      AccumulationInputError.LimitExceeded
  let emptyCompletion = default(CompletedAccumulationReentry)
  assert prepareAccumulationReentry(emptyCompletion, config(), cap).error ==
      AccumulationReentryError.InvalidSource
  let empty = default(PreparedAccumulationReentry)
  assert empty.reentryPrevious.error == AccumulationReentryError.Uninitialized
  assert second.reentryReportAt(ContinuationReportIndex(high(uint64))).error ==
      AccumulationReentryError.InvalidIndex
  var observed = second.reentryInfo.value
  observed.depth = AccumulationReentryDepth(high(uint64))
  assert uint64(second.reentryInfo.value.depth) == 2
  assert hashCalls() == 0
  failHash(0)
  let secondDone = completed(second)
  assert uint64(secondDone.executionInfo.value.gasUsed) == 44
  failHash(3)
  let third = prepareAccumulationReentry(secondDone, config(), cap).value
  assert uint64(third.reentryInfo.value.depth) == 3
  assert uint64(third.reentryInfo.value.completedPrefix) == 5
  assert uint64(third.reentryInfo.value.prefix) == 2
  assert uint64(third.reentryInfo.value.budget) == 200824
  assert hashCalls() == 0
  failHash(0)
  let thirdDone = completed(third)
  failHash(3)
  let terminal = prepareAccumulationReentry(thirdDone, config(), cap).value
  assert uint64(terminal.reentryInfo.value.depth) == 4
  assert uint64(terminal.reentryInfo.value.completedPrefix) == 7
  assert uint64(terminal.reentryInfo.value.budget) == 200780
  assert not terminal.reentryInfo.value.dispatch
  assert terminal.reentryInputs.value.invocationServiceCount.value == 0
  assert hashCalls() == 0
  failHash(0)
  let terminalDone = completed(terminal)
  failHash(3)
  let stopped = prepareAccumulationReentry(terminalDone, config(), AccumulationReentryDepthLimit(
      high(uint64)))
  assert stopped.error == AccumulationReentryError.Stopped # A terminal certificate cannot grow an idle history chain.
  assert sameStateSnapshot(fixture.initial.state.snapshot.value, first.reentryState.value)
  assert hashCalls() == 0
  failHash(0)
  let skipFixture = reentryFixture(base, first = ExecutionEnding.Missing,
    second = ExecutionEnding.Missing,
    firstGas = 100000, secondGas = 100000, tail = tail)
  let skipDone = completed(skipFixture.source)
  assert uint64(skipDone.executionInfo.value.gasUsed) == 0
  let skipNext = prepareAccumulationReentry(skipDone, config(), cap).value
  assert uint64(skipNext.reentryInfo.value.budget) == 201000
  let provided = reentryFixture(base, provided = true)
  let actual = provided.source.reentryState.value
  let prior = provided.source.reentrySource.value.executionContinuation.value.continuationState.value
  assert not sameStateSnapshot(actual, prior)
  let providedRuns = @[reentryGuest(provided.source, 0, provided = true), reentryGuest(
      provided.source, 1)]
  let providedDone = completeAccumulationReentry(provided.source, providedRuns, [], executionLimits()).value
  failHash(3)
  let providedNext = prepareAccumulationReentry(providedDone, config(), cap).value
  assert sameStateSnapshot(providedNext.reentryState.value,
      actual) # Do not reapply the initial/earlier provision batch.
  assert not sameStateSnapshot(providedNext.reentryState.value, prior)
  assert hashCalls() == 0
  failHash(0)
  let foreignNext = prepareAccumulationReentry(firstDone, config(), cap).value
  let foreignRuns = [reentryGuest(foreignNext, 0), reentryGuest(foreignNext, 1)]
  let foreign = completeAccumulationReentry(second, foreignRuns, [], executionLimits())
  assert foreign.batchFailure.error == AccumulationBatchError.SourceMismatch
  var retained: PreparedAccumulationReentry
  block:
    let local = reentryFixture(base, firstGas = 100000, secondGas = 100000, tail = tail)
    retained = prepareAccumulationReentry(completed(local.source), config(), cap).value
  assert uint64(retained.reentryPrevious.value.executionReentry.value.reentryInfo.value.depth) == 1
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    let next = prepareAccumulationReentry(firstDone, config(), cap).value
    let done = completed(next)
    failHash(3)
    let following = prepareAccumulationReentry(done, config(), cap).value
    assert uint64(following.reentryInfo.value.depth) == 3
    let refused = prepareAccumulationReentry(done, config(), AccumulationReentryDepthLimit(2))
    assert refused.error == AccumulationReentryError.LimitExceeded
    assert hashCalls() == 0
    failHash(0)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_reentry_cycle", 1000, before, after)
  echo "Repeated accumulation reentry passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Unexpected exceptions or fixture I/O failures remain native failures.
except:
  quit(2)
