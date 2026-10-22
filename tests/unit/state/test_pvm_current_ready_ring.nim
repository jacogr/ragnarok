# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_ready_ring_arc_release"}

## Genuine current completion removes only processed parent ready reports and preserves unaffordable original suffixes.
import std/[assertions, envvars, syncio]
import ../../../src/codec/[bounded, assurances, report_owned, state_layout, state_workqueues]
import ../../../src/state/[accumulation_current_ready, accumulation_ready,
  accumulation_current_finalization, accumulation_current_accounts, store]
import ../../support/[accumulation_current_outputs_context,
  accumulation_current_finalization_context,
  accumulation_ready_witnesses, report_context, arc_evidence]
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc main() {.raises.} =
  ## Complete signatures, guest execution, selected state, statistics and timestamps remain genuine prerequisites.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve report transport octets.
  let base = decodeOwnedReport(wire, 2).value
  let completed = currentOutputCompletion(base, false)
  let accounts = currentFinalizationAccounts(completed)
  let finalized = prepareCurrentAccumulationFinalization(accounts, currentFinalizationConfig()).value
  let prior = finalized.currentFinalizationState.value
  let prepared = prepareCurrentAccumulationReady(finalized, readyPolicy())
  assert prepared.error == CurrentAccumulationReadyError.None, $prepared.error
  let ready = prepared.value
  assert ready.currentReadyRing.value.readyInfo.value.items == 0, "actually processed parent report is removed"
  assert ready.currentReadyEntry.value.value == newSeq[byte](12)
  let selected = ready.currentReadyState.value
  for chapter in [15'u8, 16'u8, 250'u8]:
    let key = chapterKey(StateChapter(chapter))
    assert selected.lookup(key).value.bytes == prior.lookup(key).value.bytes, "C14 update preserves prior selected history/output/opaque state"
  assert sameStateSnapshot(ready.currentReadySource.value.currentFinalizationState.value, prior)
  let originalReady = prior.lookup(chapterKey(StateChapter(14))).value.bytes
  assert originalReady.len > 12, "private source still retains original queued report"
  var copied = ready.currentReadyEntry.value
  copied.value[0] = 77
  assert ready.currentReadyEntry.value.value[0] == 0, "fresh wire extraction cannot mutate retained ready state"
  let stopped = currentOutputCompletion(base, false, reportGas = high(uint64))
  let stoppedAccounts = currentFinalizationAccounts(stopped)
  let stoppedFinal = prepareCurrentAccumulationFinalization(stoppedAccounts,
      currentFinalizationConfig()).value
  let stoppedInfo = stoppedFinal.currentFinalizationInfo.value
  assert uint64(stoppedInfo.processed) == 0 and stoppedInfo.pendingReports == 1
  let pending = prepareCurrentAccumulationReady(stoppedFinal, readyPolicy()).value
  let ring = pending.currentReadyRing.value
  assert ring.readyInfo.value.items == 1 and ring.readySlotCount(WorkQueueSlot(0)).value == 1
  let report = ring.readyItemAt(WorkQueueSlot(0), ReadyItemIndex(0)).value.report
  let expected = reportFor(base, 0, [high(uint64)])
  assert reportBytes(report) == reportBytes(expected), "unaffordable parent report retains its exact original gas and wire"
  for field in 0..<2:
    var wrong = readyPolicy()
    if field == 0: wrong.queues.cores = CoreCount(3) # Empty posterior still belongs to authenticated core shape.
    else: wrong.queues.epochSlots = EpochSlots(13) # Ring shape cannot replace admission's epoch.
    assert prepareCurrentAccumulationReady(finalized, wrong).error ==
        CurrentAccumulationReadyError.InvalidConfig
  var codecCap = readyPolicy()
  codecCap.queues.reportBytes = ByteLimit(0)
  let malformed = prepareCurrentAccumulationReady(finalized, codecCap)
  assert malformed.error == CurrentAccumulationReadyError.CodecFailure
  assert malformed.codecFailure == WorkQueueError.LimitExceeded, "original report is charged before successful removal"
  var inspectCap = readyPolicy()
  inspectCap.items = ElementLimit(1)
  let tooSmall = prepareCurrentAccumulationReady(finalized, inspectCap)
  assert tooSmall.error == CurrentAccumulationReadyError.ProjectionFailure
  assert tooSmall.projectionFailure.error == AccumulationReadyError.LimitExceeded
  failHash(1)
  let backend = prepareCurrentAccumulationReady(finalized, readyPolicy())
  assert backend.error == CurrentAccumulationReadyError.StateFailure
  assert backend.stateFailure == StateStoreError.BackendFailure
  failHash(0)
  assert prior.lookup(chapterKey(StateChapter(14))).value.bytes == originalReady, "late failure never mutates the source ready ring"
  let invalid = prepareCurrentAccumulationReady(default(PreparedCurrentAccumulationFinalization),
      readyPolicy())
  assert invalid.error == CurrentAccumulationReadyError.InvalidSource
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCurrentAccumulationReady(finalized, readyPolicy()).value
    assert local.currentReadyRing.value.readyInfo.value.items ==
        0 # Private map and retained source graph release together.
  let after = getOccupiedMem()
  assert occupied == after, "current ready ring releases"
  recordArcRelease("pvm_current_ready_ring", 1000, occupied, after)
  echo "PVM current ready ring passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected setup/admission/ownership failures fail the suite.
except:
  quit(2)
