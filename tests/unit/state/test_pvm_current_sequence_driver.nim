# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_sequence_driver_arc_release"}

## Bounded current driving proves actual termination, exact history capacity and root/manual state parity without exposing successful prefixes on refusal.
import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, composite, report_owned, state_trie]
import ../../../src/state/[accumulation_current_driver, accumulation_current_sequence,
  accumulation_current_round, accumulation_block_guests, accumulation_round,
  accumulation_coverage, store]
import ../../support/[accumulation_current_round_context, accumulation_current_sequence_context,
    accumulation_current_driver_context, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(): CurrentSequenceDriverLimits =
  ## Keep local call sites short while sharing the maintained tiny-chain driver configuration.
  currentSequenceDriverLimits()
proc main() {.raises.} =
  ## Retain real signed admission and current proof constructors, including the initially excluded available report.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve the exact binary report fixture.
  let base = decodeOwnedReport(wire, 2).value
  let initial = currentSequenceInitialRound(base, transferGas = 100)
  let source = startCurrentAccumulationSequence(initial).value
  let before = source.currentSequenceLatestState.value
  let first = planCurrentAccumulationContinuation(source, policy().planning).value
  var copied = first.currentContinuationInfo.value
  copied.dispatch = false # Copy mutation never changes the genuine active plan.
  let active = finishCurrentAccumulationSequence(first)
  assert active.error == CurrentSequenceDriverError.Incomplete
  let driven = runCurrentAccumulationSequence(source, policy().planning, policy().execution)
  assert driven.error == CurrentSequenceDriverError.None, $driven.error
  let completed = driven.value
  let info = completed.completedSequenceInfo.value
  assert info.entries == 3 and uint64(info.processedReports) == 1 and info.pending == 0
  assert not completed.completedSequencePlan.value.currentContinuationInfo.value.dispatch
  assert completed.completedSequenceSource.value.currentSequenceCoverageAt(
      CurrentSequenceEntryIndex(2)).value.coverageInfo.value.services == 1
  let root = runCurrentBlockAccumulationSequence(initial.currentRoundGuests.value.guestRound.value,
    initial.currentRoundParameters.value, policy())
  assert root.error == CurrentSequenceDriverError.None, $root.error
  assert root.value.completedSequenceInfo.value.entries == 3
  assert array[32, byte](root.value.completedSequenceState.value.commitment.root) ==
    array[32, byte](completed.completedSequenceState.value.commitment.root), "root orchestration agrees with genuine manually started history"
  assert sameStateSnapshot(source.currentSequenceLatestState.value, before)
  var short = policy()
  short.execution.entries = ElementLimit(2)
  let limited = runCurrentAccumulationSequence(source, short.planning, short.execution)
  assert limited.error == CurrentSequenceDriverError.ExecutionFailure
  assert limited.executionFailure.error == CurrentSequenceError.LimitExceeded, "no earlier successful report entry escapes short history capacity"
  short = policy()
  short.planning.reports = ElementLimit(0)
  let planning = runCurrentAccumulationSequence(source, short.planning, short.execution)
  assert planning.error == CurrentSequenceDriverError.PlanningFailure
  assert planning.planningFailure.error == CurrentSequenceError.LimitExceeded
  short = policy()
  short.initial.guests.services = ElementLimit(1)
  let setup = runCurrentBlockAccumulationSequence(initial.currentRoundGuests.value.guestRound.value,
    initial.currentRoundParameters.value, short)
  assert setup.error == CurrentSequenceDriverError.InitialFailure
  assert setup.initialFailure.error == CurrentAccumulationRoundError.GuestFailure
  failHash(1)
  short = policy()
  short.execution.entries = ElementLimit(0)
  let zero = runCurrentBlockAccumulationSequence(initial.currentRoundGuests.value.guestRound.value,
    initial.currentRoundParameters.value, short)
  assert zero.error == CurrentSequenceDriverError.LimitExceeded and hashCalls() == 0, "initial history capacity is proved before guest work"
  failHash(0)
  assert sameStateSnapshot(source.currentSequenceLatestState.value, before)
  let unaffordable = startCurrentAccumulationSequence(currentSequenceInitialRound(base,
      empty = true)).value
  let terminal = runCurrentAccumulationSequence(unaffordable, policy().planning, policy().execution).value
  assert terminal.completedSequenceInfo.value.entries == 1
  assert terminal.completedSequencePlan.value.currentContinuationInfo.value.pendingReports == 1, "an unaffordable original report stays for a later block"
  let refused = finishCurrentAccumulationSequence(default(PreparedCurrentContinuation))
  assert refused.error == CurrentSequenceDriverError.InvalidPlan
  let absentPolicy = policy()
  let absent = runCurrentAccumulationSequence(default(CurrentAccumulationSequence),
    absentPolicy.planning, absentPolicy.execution)
  assert absent.error == CurrentSequenceDriverError.InvalidSequence
  assert default(CompletedCurrentAccumulationSequence).completedSequenceState.error ==
      CurrentSequenceDriverError.Uninitialized
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = runCurrentAccumulationSequence(source, policy().planning, policy().execution).value
    assert local.completedSequenceInfo.value.entries ==
        3 # Bounded driving releases temporary plans, earlier vectors and final terminal owners.
  let after = getOccupiedMem()
  assert occupied == after, "current terminal sequence owners release"
  recordArcRelease("pvm_current_sequence_driver", 1000, occupied, after)
  echo "PVM current sequence driver passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Admission/native setup and unexpected failures remain strict native suite failures.
except:
  quit(2)
