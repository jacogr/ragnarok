# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_recent_history_arc_release"}

## Current C3 derives sealed header, output root and guarantee dictionary from one genuine terminal source.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/header as codec_header
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_history as codec_state_history
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/state/accumulation_current_recent as state_accumulation_current_recent
import ../../../src/state/accumulation_recent as state_accumulation_recent
import ../../../src/state/accumulation_current_ready as state_accumulation_current_ready
import ../../../src/state/accumulation_current_finalization as state_accumulation_current_finalization
import ../../../src/state/accumulation_current_accounts as state_accumulation_current_accounts
import ../../../src/state/accumulation_current_statistics as state_accumulation_current_statistics
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ../../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
import ../../../src/state/accumulation_current_round as state_accumulation_current_round
import ../../../src/state/accumulation_block_guests as state_accumulation_block_guests
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/guarantee_credentials as state_guarantee_credentials
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/history as state_history
import ../../../src/state/store as state_store
import ../../support/state_accumulation_current_recent_context
import ../../support/state_accumulation_recent_witnesses
import ../../support/testing_arc_evidence
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc checkSource(source: PreparedCurrentAccumulationReady,
    incoming: bool): PreparedCurrentAccumulationRecent =
  ## Observe original admission independently and compare exact current history fields and signed-header identity.
  let finalization = source.currentReadySource.value
  let completed = finalization.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value
  let sequence = completed.completedSequenceSource.value
  let admission = sequence.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value
  let binding = admission.reportBlockStage.value.value.admitted
  let header = binding.admittedHeader
  let metadata = header.headerInfo.value
  var bytes = newSeq[byte](metadata.consumed)
  assert header.encodeOwnedHeader(bytes).error == HeaderError.None
  let sealed = array[32, byte](blake2b256(bytes).value)
  let unsigned = array[32, byte](blake2b256(bytes.toOpenArray(0,
      metadata.unsigned.consumed-1)).value)
  assert sealed != unsigned, "sealed-header hash includes the signature"
  let prepared = prepareCurrentAccumulationRecent(source, recentPolicy())
  assert prepared.error == CurrentAccumulationRecentError.None, $prepared.error
  let recent = prepared.value
  let history = recent.currentRecentHistory.value
  assert history.historyInfo.value.blocks == 2 and history.historyInfo.value.peaks == 1
  let parent = history.historyBlockAt(HistoryBlockIndex(0)).value
  let latest = history.historyBlockAt(HistoryBlockIndex(1)).value
  assert array[32, byte](parent.state) == array[32, byte](metadata.unsigned.priorState), "previous record receives exact admitted parent commitment"
  assert array[32, byte](parent.state) != array[32, byte](
      recent.currentRecentState.value.commitment.root)
  assert array[32, byte](latest.header) == sealed and uint32(latest.slot) == 2
  assert array[32, byte](latest.state) == default(array[32, byte]), "newest record has the canonical unfilled state field"
  let root = array[32, byte](recent.currentRecentRoot.value)
  assert array[32, byte](latest.superPeak) == root
  assert array[32, byte](history.historyPeakAt(HistoryPeakIndex(0)).value.hash) == root
  if incoming:
    assert latest.packages == 1
    let guaranteed = admission.reportCredentials.value.verifiedGuaranteeAt(
        0).value.report.ownedReportInfo.value.header
    let reported = history.historyPackageAt(HistoryBlockIndex(1), HistoryPackageIndex(0)).value
    assert reported.package.bytes == guaranteed.packageHash.bytes and reported.segment.bytes ==
        guaranteed.segmentRoot.bytes
    assert uint64(finalization.currentFinalizationInfo.value.processed) == 0, "new guarantee is distinct from processed work"
    assert root == default(array[32, byte]), "halt-only guests yield no output root"
  else:
    assert latest.packages == 0 and uint64(finalization.currentFinalizationInfo.value.processed) ==
        1, "processed ready package never becomes a new guarantee"
    var leaves = newSeq[byte](76)
    leaves[0] = byte('n'); leaves[1] = byte('o'); leaves[2] = byte('d'); leaves[3] = byte('e')
    leaves[4] = 42; leaves[8] = 73; leaves[40] = 99; leaves[44] = 73
    assert root == array[32, byte](keccak256(leaves).value), "literal node domain and two raw E4/hash leaves define the independent expected root"
  let selected = recent.currentRecentState.value
  let prior = source.currentReadyState.value
  for chapter in [14'u8, 15'u8, 16'u8, 250'u8]:
    let key = chapterKey(StateChapter(chapter))
    assert selected.lookup(key).value.bytes == prior.lookup(key).value.bytes, "C3 preserves all prior selected stages"
  assert sameStateSnapshot(recent.currentRecentSource.value.currentReadyState.value, prior)
  var detached = recent.currentRecentEntry.value
  detached.value[0] = 77
  assert recent.currentRecentEntry.value.value[0] == 2, "entry extraction owns fresh bytes"
  recent
proc main() {.raises.} =
  ## Real signed predecessors exercise both report roles without synthetic sources or detached roots.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve exact report transport.
  let base = decodeOwnedReport(wire, 2).value
  let source = currentRecentReady(base)
  discard checkSource(source, false)
  discard checkSource(currentRecentReady(base, incoming = true), true)
  for mode in 0..<4:
    var limited = recentPolicy()
    case mode
    of 0: limited.headerBytes = ByteLimit(0) # Sealed header capture is independently bounded.
    of 1: limited.outputs.items = ElementLimit(1) # Complete selected pair root work cannot truncate.
    of 2: limited.outputs.maxBytes = ByteLimit(72) # Count prefix participates in exact complete log extent.
    else: limited.history.maxBytes = ByteLimit(0) # Original C3 bytes are charged before copying.
    assert prepareCurrentAccumulationRecent(source, limited).error ==
        CurrentAccumulationRecentError.LimitExceeded
  var wrong = recentPolicy()
  wrong.history.cores = CoreCount(3)
  assert prepareCurrentAccumulationRecent(source, wrong).error ==
      CurrentAccumulationRecentError.InvalidConfig
  var noPeaks = recentPolicy()
  noPeaks.history.peaks = ElementLimit(0)
  let historyFailure = prepareCurrentAccumulationRecent(source, noPeaks)
  assert historyFailure.error == CurrentAccumulationRecentError.HistoryFailure
  assert historyFailure.historyError == HistoryTransitionError.LimitExceeded
  failHash(2)
  let outputFailure = prepareCurrentAccumulationRecent(source, recentPolicy())
  assert outputFailure.error == CurrentAccumulationRecentError.OutputFailure
  assert outputFailure.outputError == HistoryTransitionError.BackendFailure
  failHash(1)
  assert prepareCurrentAccumulationRecent(source, recentPolicy()).error ==
      CurrentAccumulationRecentError.BackendFailure
  failHash(0)
  failAfter(1)
  let stateFailure = prepareCurrentAccumulationRecent(source, recentPolicy())
  assert stateFailure.error == CurrentAccumulationRecentError.StateFailure
  assert stateFailure.stateError == StateStoreError.BackendFailure
  failHash(0)
  assert source.currentReadyState.value.lookup(chapterKey(StateChapter(3))).value.bytes[0] == 1, "late hashing refusal leaves original C3 unchanged"
  let invalid = prepareCurrentAccumulationRecent(default(PreparedCurrentAccumulationReady),
      recentPolicy())
  assert invalid.error == CurrentAccumulationRecentError.InvalidSource
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCurrentAccumulationRecent(source, recentPolicy()).value
    assert local.currentRecentHistory.value.historyInfo.value.blocks ==
        2 # Private C3 and retained current proof graph release together.
  let after = getOccupiedMem()
  assert occupied == after, "current recent history releases"
  recordArcRelease("pvm_current_recent_history", 1000, occupied, after)
  echo "PVM current recent history passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected setup/admission/ownership failures fail the suite.
except:
  quit(2)
