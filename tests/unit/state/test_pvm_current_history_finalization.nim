# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_history_finalization_arc_release"}

## Same-source C15 and C16 publish together after admitted-time metadata updates, retaining exact terminal progress.
import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, assurances, report_owned]
import ../../../src/codec/state/[accounts as state_accounts, layout as state_layout,
    outputs as state_outputs, workqueues as state_workqueues]
import ../../../src/state/accumulation/current/[finalization as accumulation_current_finalization,
    accounts as accumulation_current_accounts, outputs as accumulation_current_outputs,
    driver as accumulation_current_driver, sequence as accumulation_current_sequence]
import ../../../src/state/accumulation/history as accumulation_history
import ../../../src/state/store
import ../../support/[accumulation_current_finalization_context,
  accumulation_current_outputs_context,
  accumulation_current_statistics_context, accumulation_current_sequence_context,
  accumulation_current_driver_context, report_context, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc main() {.raises.} =
  ## Sources are real signed terminal current sequences; expected C15 framing is authored independently.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve report transport octets.
  let base = decodeOwnedReport(wire, 2).value
  let completed = currentOutputCompletion(base, false)
  let accounts = currentFinalizationAccounts(completed)
  let prior = accounts.currentAccountsState.value
  let prepared = prepareCurrentAccumulationFinalization(accounts, currentFinalizationConfig())
  assert prepared.error == CurrentAccumulationFinalizationError.None, $prepared.error
  let finalized = prepared.value
  let info = finalized.currentFinalizationInfo.value
  assert uint64(info.processed) == 1 and info.pendingReports == 0
  assert info.history.slots == 12 and info.history.newPackages == 1 and info.history.packages == 1
  let selected = finalized.currentFinalizationState.value
  let processed = reportFor(base, 0, [10000'u64]).ownedReportInfo.value.header.packageHash
  var expected = newSeq[byte](11)
  expected.add(1)
  for octet in processed.bytes: expected.add(octet) # Eleven empty rows precede the exact one-hash newest set.
  let historyKey = chapterKey(StateChapter(15))
  assert selected.lookup(historyKey).value.bytes == expected, "processed original prefix shifts history exactly once"
  assert prior.lookup(historyKey).value.bytes == newSeq[byte](12), "source ring remains unchanged"
  let outputs = finalized.currentFinalizationOutputs.value
  assert selected.lookup(chapterKey(StateChapter(16))).value.bytes ==
      outputs.currentOutputsEntry.value.value
  assert finalized.currentFinalizationHistory.value.accumulatedHashAt(WorkQueueSlot(11),
      WorkQueueHashIndex(0)).value.bytes == processed.bytes
  assert sameStateSnapshot(finalized.currentFinalizationAccounts.value.currentAccountsState.value, prior)
  for id in [42'u32, 99'u32]:
    let key = chapterServiceKey(StateChapter(255), ServiceIndex(id))
    assert selected.lookup(key).value.bytes == prior.lookup(key).value.bytes, "C15/C16 update preserves all timestamped metadata"
  let stoppedInitial = currentSequenceInitialRound(base, empty = true)
  let driver = currentSequenceDriverLimits()
  let stopped = runCurrentAccumulationSequence(startCurrentAccumulationSequence(
      stoppedInitial).value,
    driver.planning, driver.execution).value
  let stoppedAccounts = currentFinalizationAccounts(stopped)
  let unprocessed = prepareCurrentAccumulationFinalization(stoppedAccounts,
      currentFinalizationConfig()).value
  let stoppedInfo = unprocessed.currentFinalizationInfo.value
  assert uint64(stoppedInfo.processed) == 0 and stoppedInfo.pendingReports == 1, "budget stop is distinct from exhausted queue"
  assert unprocessed.currentFinalizationState.value.lookup(historyKey).value.bytes == newSeq[byte](12)
  for scenario in [CurrentStatisticsScenario.ZeroParticipants, CurrentStatisticsScenario.Annulled]:
    let source = currentStatisticsCompletion(base, scenario)
    let selectedAccounts = currentFinalizationAccounts(source)
    let empty = prepareCurrentAccumulationFinalization(selectedAccounts, currentFinalizationConfig()).value
    assert empty.currentFinalizationOutputs.value.currentOutputsInfo.value.outputs == 0, "absent/annulled originals never enter published C16"
  for field in 0..<2:
    var invalidProfile = currentFinalizationConfig()
    if field == 0: invalidProfile.history.queues.cores = CoreCount(3) # Admission binds the exact core shape.
    else: invalidProfile.history.queues.epochSlots = EpochSlots(
        13) # Even empty history uses the authenticated epoch.
    assert prepareCurrentAccumulationFinalization(stoppedAccounts, invalidProfile).error ==
        CurrentAccumulationFinalizationError.InvalidConfig
  var reports = currentFinalizationConfig()
  reports.history.reports = ElementLimit(0)
  assert prepareCurrentAccumulationFinalization(accounts, reports).error ==
      CurrentAccumulationFinalizationError.LimitExceeded
  var outputCap = currentFinalizationConfig()
  outputCap.outputs.log.items = ElementLimit(1)
  let refusedOutput = prepareCurrentAccumulationFinalization(accounts, outputCap)
  assert refusedOutput.error == CurrentAccumulationFinalizationError.OutputFailure
  assert refusedOutput.outputFailure.error == CurrentAccumulationOutputsError.LimitExceeded
  var historyCap = currentFinalizationConfig()
  historyCap.history.queues.maxBytes = ByteLimit(43)
  let refusedHistory = prepareCurrentAccumulationFinalization(accounts, historyCap)
  assert refusedHistory.error == CurrentAccumulationFinalizationError.ProjectionFailure
  assert refusedHistory.projectionFailure.error == AccumulationHistoryError.CodecFailure
  assert refusedHistory.projectionFailure.codecError == WorkQueueError.LimitExceeded
  failHash(1)
  let backend = prepareCurrentAccumulationFinalization(accounts, currentFinalizationConfig())
  assert backend.error == CurrentAccumulationFinalizationError.StateFailure
  assert backend.stateFailure == StateStoreError.BackendFailure
  failHash(0)
  assert prior.lookup(historyKey).value.bytes == newSeq[byte](12), "late failure publishes neither C15 nor C16 prefix"
  let invalid = prepareCurrentAccumulationFinalization(default(PreparedCurrentAccumulationAccounts),
      currentFinalizationConfig())
  assert invalid.error == CurrentAccumulationFinalizationError.InvalidSource
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCurrentAccumulationFinalization(accounts, currentFinalizationConfig()).value
    assert local.currentFinalizationInfo.value.history.newPackages ==
        1 # Private maps and proof graph release together.
  let after = getOccupiedMem()
  assert occupied == after, "current history finalization releases"
  recordArcRelease("pvm_current_history_finalization", 1000, occupied, after)
  echo "PVM current history finalization passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected admission/native/ownership failures must fail the suite.
except:
  quit(2)
