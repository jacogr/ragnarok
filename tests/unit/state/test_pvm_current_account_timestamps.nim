# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_account_timestamps_arc_release"}

## Real current statistics authorize exact final-present metadata timestamps, never account resurrection.
import std/assertions
import std/envvars
import std/syncio
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/state/accumulation_current_accounts as state_accumulation_current_accounts
import ../../../src/state/accumulation_accounts as state_accumulation_accounts
import ../../../src/state/accumulation_current_statistics as state_accumulation_current_statistics
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ../../../src/state/store as state_store
import ../../support/state_accumulation_current_statistics_context
import ../../support/testing_arc_evidence
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
proc policy(): AccumulationAccountConfig =
  ## Two fixed metadata records suffice for every ordinary final-present participant.
  AccumulationAccountConfig(services: ElementLimit(2), metadataBytes: ByteLimit(210))
proc metadata(state: StateStoreSnapshot, id: uint32): ServiceMetadata =
  ## Observe exact selected metadata through the public complete-map interface.
  let wire = state.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(id))).value.bytes
  decodeServiceMetadata(wire, ByteLimit(ServiceMetadataBytes)).value.metadata
proc main() {.raises.} =
  ## All source graphs pass real signature/admission and current guest/selection constructors.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index]) # Preserve report transport octets.
  let base = decodeOwnedReport(wire, 2).value
  let completed = currentStatisticsCompletion(base, CurrentStatisticsScenario.Transfers)
  let statistics = prepareCurrentAccumulationStatistics(completed, currentStatisticsLimits()).value
  let prior = completed.completedSequenceState.value
  let prepared = prepareCurrentAccumulationAccounts(statistics, policy())
  assert prepared.error == CurrentAccumulationAccountError.None, $prepared.error
  let accounts = prepared.value
  let info = accounts.currentAccountsInfo.value
  assert uint32(info.slot) == 2 and info.services == 2 and info.accounts == 2 and info.updates == 2
  let updated = accounts.currentAccountsState.value
  for id in [42'u32, 99'u32]:
    var expected = metadata(prior, id)
    assert uint32(expected.lastAccumulation) == 0, "source account remains at original time"
    expected.lastAccumulation = AccountSlot(2)
    let encoded = serviceMetadataEntry(ServiceIndex(id), expected, ByteLimit(
        ServiceMetadataBytes)).value
    assert updated.lookup(encoded.key).value.bytes == encoded.value, "only admitted-time field changes"
  assert sameStateSnapshot(accounts.currentAccountsSource.value.currentStatisticsSource.value.completedSequenceState.value, prior)
  let skipped = currentStatisticsCompletion(base, CurrentStatisticsScenario.SkippedReport)
  let skippedStatistics = prepareCurrentAccumulationStatistics(skipped, currentStatisticsLimits()).value
  let selected = prepareCurrentAccumulationAccounts(skippedStatistics, policy()).value
  assert uint32(metadata(selected.currentAccountsState.value, 42).lastAccumulation) == 2
  assert uint32(metadata(selected.currentAccountsState.value, 99).lastAccumulation) == 0, "all-zero provider has no statistics key"
  let empty = currentStatisticsCompletion(base, CurrentStatisticsScenario.ZeroParticipants)
  let emptyStatistics = prepareCurrentAccumulationStatistics(empty, currentStatisticsLimits()).value
  failHash(1)
  let unchanged = prepareCurrentAccumulationAccounts(emptyStatistics, default(AccumulationAccountConfig))
  assert unchanged.error == CurrentAccumulationAccountError.None
  assert hashCalls() == 0, "zero statistics require no metadata writes or hashing"
  assert sameStateSnapshot(unchanged.value.currentAccountsState.value,
      empty.completedSequenceState.value)
  failHash(0)
  let ejected = currentStatisticsCompletion(base, CurrentStatisticsScenario.EjectedTransfer)
  let ejectedStatistics = prepareCurrentAccumulationStatistics(ejected, currentStatisticsLimits()).value
  var onePresent = policy()
  onePresent.metadataBytes = ByteLimit(105)
  let finalPresent = prepareCurrentAccumulationAccounts(ejectedStatistics, onePresent).value
  let presentInfo = finalPresent.currentAccountsInfo.value
  assert presentInfo.services == 2 and presentInfo.accounts == 1 and presentInfo.updates == 1
  assert finalPresent.currentAccountsState.value.lookup(chapterServiceKey(StateChapter(255),
      ServiceIndex(99))).error == StateStoreError.MissingKey, "counted ejected recipient never reappears"
  let annulled = currentStatisticsCompletion(base, CurrentStatisticsScenario.Annulled)
  let originalGas = prepareCurrentAccumulationStatistics(annulled, currentStatisticsLimits()).value
  let retained = prepareCurrentAccumulationAccounts(originalGas, policy()).value
  assert uint32(metadata(retained.currentAccountsState.value, 99).lastAccumulation) == 2, "original annulled gas still participates in S"
  var countCap = policy()
  countCap.services = ElementLimit(1)
  assert prepareCurrentAccumulationAccounts(statistics, countCap).error ==
      CurrentAccumulationAccountError.LimitExceeded
  var byteCap = policy()
  byteCap.metadataBytes = ByteLimit(209)
  let tooSmall = prepareCurrentAccumulationAccounts(statistics, byteCap)
  assert tooSmall.error == CurrentAccumulationAccountError.ProjectionFailure
  assert tooSmall.projectionFailure.error == AccumulationAccountError.LimitExceeded
  failHash(1)
  let refused = prepareCurrentAccumulationAccounts(statistics, policy())
  assert refused.error == CurrentAccumulationAccountError.StateFailure
  assert refused.stateFailure == StateStoreError.BackendFailure
  failHash(0)
  assert uint32(metadata(prior, 42).lastAccumulation) == 0, "late backend refusal leaves source unchanged"
  let invalid = prepareCurrentAccumulationAccounts(default(PreparedCurrentAccumulationStatistics),
      policy())
  assert invalid.error == CurrentAccumulationAccountError.InvalidSource
  let occupied = getOccupiedMem()
  for iteration in 0..<1000:
    let local = prepareCurrentAccumulationAccounts(statistics, policy()).value
    assert local.currentAccountsInfo.value.updates == 2 # Private maps and retained statistics release together.
  let after = getOccupiedMem()
  assert occupied == after, "current account timestamp ownership releases"
  recordArcRelease("pvm_current_account_timestamps", 1000, occupied, after)
  echo "PVM current account timestamps passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main() # Unexpected admission, native setup and ownership failures fail the suite.
except:
  quit(2)
