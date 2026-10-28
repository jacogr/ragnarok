# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_continuation_execution_arc_release"}

## Current report-only and held-transfer-only entries use frozen parameters/frame and consume gas without restoring old queued reservations.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/chain/parameters as chain_parameters
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/header as codec_header
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/pvm/step as pvm_step
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
import ../../../src/state/accumulation_current_round as state_accumulation_current_round
import ../../../src/state/accumulation_block_guests as state_accumulation_block_guests
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/accumulation_coverage as state_accumulation_coverage
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/accumulation_effects as state_accumulation_effects
import ../../../src/state/accumulation_context as state_accumulation_context
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
import ../../../src/state/accumulation_guest_runner as state_accumulation_guest_runner
import ../../../src/state/accumulation_account_phase as state_accumulation_account_phase
import ../../../src/state/accumulation_provision_phase as state_accumulation_provision_phase
import ../../../src/state/accumulation_global_phase as state_accumulation_global_phase
import ../../../src/state/accumulation_annulled_outputs as state_accumulation_annulled_outputs
import ../../../src/state/accumulation_transfers as state_accumulation_transfers
import ../../../src/state/accumulation_pending_transfers as state_accumulation_pending_transfers
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../../src/state/store as state_store
import ../../support/state_accumulation_current_round_context
import ../../support/state_accumulation_current_sequence_context
import ../../support/testing_arc_evidence
proc policy(): CurrentContinuationExecutionLimits =
  ## Three facts include the initial entry, report-only execution and eventual held-transfer delivery.
  CurrentContinuationExecutionLimits(entries: ElementLimit(3), round: currentRoundLimits())
proc frame(sequence: CurrentAccumulationSequence, index: uint64) =
  ## Every actual later bootstrap retains the original admitted header slot and posterior C6 word, not selected-map entropy.
  let anchor = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value
  let expected = decodeStateEntropy(anchor.snapshot.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value[0]
  let coverage = sequence.currentSequenceCoverageAt(CurrentSequenceEntryIndex(index)).value
  let original = coverage.coverageOriginalAt(AccumulationCoverageIndex(0)).value
  let actual = original.outcomeContext.value.effectInitialContext.value.contextInvocation.value.bootstrapInfo.value
  let expectedSlot = headerInfo(anchor.admitted.admittedHeader).value.unsigned.slot
  assert uint32(actual.slot) == uint32(expectedSlot), "actual continuation uses admitted header slot"
  assert uint32(actual.slot) == uint32(coverage.coverageInfo.value.slot), "continuation check: uint32(actual.slot) == uint32(coverage.coverageInfo.value.slot)"
  assert array[32, byte](actual.entropy) == array[32, byte](expected), "actual continuation uses posterior entropy authority"
proc main() {.raises.} =
  ## Maintained fixture admission provides a real original queue and immutable chain configuration.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact binary report framing.
  let base = decodeOwnedReport(wire, 2).value
  let initial = currentSequenceInitialRound(base, transferGas = 100)
  let source = startCurrentAccumulationSequence(initial).value
  let firstPlan = planCurrentAccumulationContinuation(source, currentContinuationLimits()).value
  let before = source.currentSequenceLatestState.value
  var detached = encodeParameters(initial.currentRoundParameters.value)
  detached[110] = 1 # Mutating a detached encoding cannot replace retained actual chain parameters.
  assert initial.currentRoundParameters.value.get(transferMemoSize) == 128, "continuation check: initial.currentRoundParameters.value.get(transferMemoSize) == 128"
  let executed = runCurrentAccumulationContinuation(firstPlan, policy())
  assert executed.error == CurrentSequenceError.None, $executed.error
  let reportEntry = executed.value
  let info = reportEntry.currentSequenceInfo.value
  assert info.entries == 2 and uint64(info.processedReports) == 1 and info.pending == 1, "continuation check: info.entries == 2 and uint64(info.processedReports) == 1 and info.pending == 1"
  let coverage = reportEntry.currentSequenceCoverageAt(CurrentSequenceEntryIndex(1)).value
  assert coverage.coverageInfo.value.services == 1 and uint64(
      coverage.coverageInfo.value.gasUsed) == 0, "report coverage services/executed/skipped/absent/gas: " &
          $coverage.coverageInfo.value.services & ":" & $coverage.coverageInfo.value.executed &
          ":" & $coverage.coverageInfo.value.skipped & ":" & $coverage.coverageInfo.value.absent &
          ":" & $uint64(coverage.coverageInfo.value.gasUsed)
  assert uint32(coverage.coverageRowAt(AccumulationCoverageIndex(0)).value.service) == 42, "continuation check: uint32(coverage.coverageRowAt(AccumulationCoverageIndex(0)).value.service) == 42"
  let pending = reportEntry.currentSequencePending.value.pendingTransferInfo.value
  assert pending.carried == 1 and pending.outgoing == 0 and uint64(pending.carriedGas) == 100, "continuation check: pending.carried == 1 and pending.outgoing == 0 and uint64(pending.carriedGas) == 100"
  assert uint64(pending.budget) == uint64(firstPlan.currentContinuationInfo.value.budget), "old held gas is never restored a second time"
  let reportOutcome = coverage.coverageOriginalAt(AccumulationCoverageIndex(0)).value
  assert reportOutcome.outcomeInfo.value.termination == AccumulationTermination.OutOfGas, "unpaid whole block retains offered gas"
  frame(reportEntry, 1)
  let secondPlan = planCurrentAccumulationContinuation(reportEntry, currentContinuationLimits()).value
  let secondInfo = secondPlan.currentContinuationInfo.value
  assert uint64(secondInfo.prefix) == 0 and secondInfo.accepted == 1 and secondInfo.queued == 0 and
      secondInfo.services == 1, "continuation check: uint64(secondInfo.prefix) == 0 and secondInfo.accepted == 1 and secondInfo.queued == 0 and secondInfo.services == 1"
  let transferEntry = runCurrentAccumulationContinuation(secondPlan, policy()).value
  let transferInfo = transferEntry.currentSequenceInfo.value
  assert transferInfo.entries == 3 and uint64(transferInfo.processedReports) == 1 and
      transferInfo.pending == 0, "continuation check: transferInfo.entries == 3 and uint64(transferInfo.processedReports) == 1 and transferInfo.pending == 0"
  let transferCoverage = transferEntry.currentSequenceCoverageAt(CurrentSequenceEntryIndex(2)).value
  assert transferCoverage.coverageInfo.value.services == 1 and uint64(
      transferCoverage.coverageInfo.value.gasUsed) == 22, "continuation check: transferCoverage.coverageInfo.value.services == 1 and uint64( transferCoverage.coverageInfo.value.gasUsed) == 22"
  assert uint32(transferCoverage.coverageRowAt(AccumulationCoverageIndex(0)).value.service) == 99, "held transfer executes without repeated report/free allowances"
  assert uint64(transferInfo.budget) == uint64(pending.budget)-22, "continuation check: uint64(transferInfo.budget) == uint64(pending.budget)-22"
  frame(transferEntry, 2)
  assert sameStateSnapshot(source.currentSequenceLatestState.value, before), "later private branches never publish earlier source state"
  let terminal = planCurrentAccumulationContinuation(transferEntry, currentContinuationLimits()).value
  var observation = terminal.currentContinuationInfo.value
  assert not observation.dispatch, "continuation check: not observation.dispatch"
  observation.dispatch = true # Copied observations cannot retag a genuine terminal owner.
  assert runCurrentAccumulationContinuation(terminal, policy()).error ==
      CurrentSequenceError.NoDispatch, "continuation check: runCurrentAccumulationContinuation(terminal, policy()).error == CurrentSequenceError.NoDispatch"
  for mode in 0..<9:
    var limits = policy()
    var expected = CurrentSequenceError.Uninitialized
    case mode
    of 0:
      limits.entries = ElementLimit(1)
      expected = CurrentSequenceError.LimitExceeded
    of 1:
      limits.round.guests.contexts.queues.cores = CoreCount(3)
      expected = CurrentSequenceError.InvalidParameters
    of 2:
      limits.round.guests.steps = ExecutionStepLimit(0)
      expected = CurrentSequenceError.GuestFailure
    of 3:
      limits.round.accounts.entries = ElementLimit(0)
      expected = CurrentSequenceError.AccountFailure
    of 4:
      limits.round.provisions.contexts = ElementLimit(0)
      expected = CurrentSequenceError.ProvisionFailure
    of 5:
      limits.round.globals.totalBytes = ByteLimit(0)
      expected = CurrentSequenceError.GlobalFailure
    of 6:
      limits.round.outputs.outcomes = ElementLimit(0)
      expected = CurrentSequenceError.OutputFailure
    of 7:
      limits.round.transfers.sources = ElementLimit(0)
      expected = CurrentSequenceError.TransferFailure
    else:
      limits.round.pending.sources = ElementLimit(0)
      expected = CurrentSequenceError.PendingFailure
    let target = if mode == 2: secondPlan else: firstPlan # The funded halt reaches an actual step attempt; the report entry is unaffordable before any instruction.
    let failed = runCurrentAccumulationContinuation(target, limits)
    assert failed.error == expected, $mode & ":" & $failed.error
    if mode == 2:
      assert failed.guestFailure.error == AccumulationGuestError.DispatchFailure, "actual step refusal remains a guest engine failure"
      assert failed.guestFailure.dispatchFailure.executionError == StepError.StepLimitExceeded, "continuation check: failed.guestFailure.dispatchFailure.executionError == StepError.StepLimitExceeded"
    assert sameStateSnapshot(source.currentSequenceLatestState.value, before), "continuation check: sameStateSnapshot(source.currentSequenceLatestState.value, before)"
  let refused = runCurrentAccumulationContinuation(default(PreparedCurrentContinuation), policy())
  assert refused.error == CurrentSequenceError.InvalidSource, "continuation check: refused.error == CurrentSequenceError.InvalidSource"
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = runCurrentAccumulationContinuation(firstPlan, policy()).value
    let next = planCurrentAccumulationContinuation(local, currentContinuationLimits()).value
    let delivered = runCurrentAccumulationContinuation(next, policy()).value
    assert delivered.currentSequenceInfo.value.entries ==
        3 # Fresh flat fact vectors share proof/state owners without retaining predecessor sequence/plan certificates., "continuation check: delivered.currentSequenceInfo.value.entries == 3 # Fresh flat fact vectors share proof/state owners without retaining pr"
  let after = getOccupiedMem()
  assert occupied == after, "current continuation execution releases flat facts and phases"
  recordArcRelease("pvm_current_continuation_execution", 1000, occupied, after)
  echo "PVM current continuation execution passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Admission, native setup and unexpected exceptions must fail the suite.
except:
  quit(2)
