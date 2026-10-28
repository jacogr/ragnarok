# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual signed current sequences retain only selected storage identities and preserve bounded original history independently of caller scope.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import ../support/state_accumulation_execution_context
import ../support/state_accumulation_current_round_context
import ../support/state_accumulation_current_driver_context
import ../support/pvm_accumulation_program
import ../support/testing_arc_evidence
import ../../src/state/accumulation_storage_history as state_accumulation_storage_history
import ../../src/state/accumulation_effects as state_accumulation_effects
import ../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../src/state/accumulation_coverage as state_accumulation_coverage
import ../../src/state/accumulation_current_sequence as state_accumulation_current_sequence
import ../../src/state/accumulation_current_driver as state_accumulation_current_driver
import ../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ../../src/codec/report_owned as codec_report_owned
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Pure selected history capture must remain usable while cryptographic backends refuse.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Whole-capture policies precede output retention without hashing.
const limits = StorageHistoryLimits(entries: ElementLimit(8), outcomes: ElementLimit(16),
    facts: ElementLimit(16), bytes: ByteLimit(65536))
proc program(target: uint64): seq[byte] =
  ## A real write of one present byte uses a known raw key; both supervisor and junior target the same account.
  currentRoundServiceCode(@[registerImmediate(7, target), registerImmediate(8, 65536),
      registerImmediate(9, 1), registerImmediate(10, 196608), registerImmediate(11, 1),
      @[10'u8, 5], @[50'u8, 0]])
proc completed(base: OwnedReport, capture = true, conflict = true): CompletedCurrentAccumulationSequence =
  ## Genuine parent signatures, actual current guests, annulment/account publication and terminal driving supply every opaque owner.
  var options = executionFixtureConfig()
  options.firstProgram = program(if conflict: 99'u64 else: high(uint64))
  options.secondProgram = program(high(uint64))
  options.secondSupervisor = 42
  options.secondBalance = 1000000
  let fixture = executionFixture(base, options)
  var policy = currentSequenceDriverLimits()
  if capture:
    policy.initial.guests.storageFacts = AccumulationStorageFactLimits(items: ElementLimit(2),
        perKey: ByteLimit(1), totalKeyBytes: ByteLimit(2))
    policy.execution.round.guests.storageFacts = policy.initial.guests.storageFacts
  let done = runCurrentBlockAccumulationSequence(fixture.round, currentRoundParameters(), policy)
  assert done.error == CurrentSequenceDriverError.None, $done.error
  done.value
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(StorageHistoryResult[StorageHistory])
  if mode == "value":
    discard empty.value
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for i in 0..<raw.len: wire[i] = byte(raw[i]) # Preserve independently pinned report bytes.
  let base = decodeOwnedReport(wire, 2).value
  let source = completed(base)
  let selected = source.completedSequenceSource.value.currentSequenceCoverageAt(
      CurrentSequenceEntryIndex(0)).value.coverageAnnulment.value
  assert selected.annulmentInfo.value.annulled == 1
  let discarded = selected.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(
      1)).value.outcomeContext.value
  assert discarded.effectStorageFactCount.value == 1
  assert selected.annulmentSelectedStorageFactCountAt(AccumulationAnnulmentIndex(1)).value == 0
  assert selected.annulmentSelectedStorageFactAt(AccumulationAnnulmentIndex(1),
      AccumulationStorageFactIndex(0)).error == AccumulationAnnulmentError.InvalidIndex
  let disabled = completed(base, capture = false)
  assert captureStorageHistory(disabled, limits).error == StorageHistoryError.StorageFactsDisabled
  let separate = completed(base, conflict = false)
  assert captureStorageHistory(separate, limits).value.storageHistoryInfo.value.facts == 2
  fail(1)
  let kept = captureStorageHistory(source, limits).value
  let info = kept.storageHistoryInfo.value
  assert info.entries == 1 and info.outcomes == 2 and info.facts == 1 and calls() == 0
  assert info.bytes == uint64(sizeof(StorageHistoryRow)+1)
  let first = kept.storageHistoryAt(StorageHistoryIndex(0)).value
  assert uint64(first.entry) == 0 and uint64(first.outcome) == 0
  assert uint32(first.fact.storageFactInfo.value.service) == 99
  assert first.fact.copyStorageFactKey(ByteLimit(1)).value.len == 1
  var short = limits
  short.entries = ElementLimit(0)
  assert captureStorageHistory(source, short).error == StorageHistoryError.LimitExceeded
  short = limits
  short.outcomes = ElementLimit(1)
  assert captureStorageHistory(source, short).error == StorageHistoryError.LimitExceeded
  short = limits
  short.facts = ElementLimit(0)
  assert captureStorageHistory(source, short).error == StorageHistoryError.LimitExceeded
  short = limits
  short.bytes = ByteLimit(info.bytes-1)
  assert captureStorageHistory(source, short).error == StorageHistoryError.LimitExceeded
  short.bytes = ByteLimit(info.bytes)
  assert captureStorageHistory(source, short).value.storageHistoryInfo.value.bytes == info.bytes
  assert calls() == 0
  assert captureStorageHistory(default(CompletedCurrentAccumulationSequence), limits).error ==
      StorageHistoryError.InvalidSource
  assert kept.storageHistoryAt(StorageHistoryIndex(high(uint64))).error ==
      StorageHistoryError.InvalidIndex
  assert default(StorageHistory).storageHistorySource.error == StorageHistoryError.InvalidSource
  fail(0)
  var escaped = default(StorageHistory)
  block retired:
    let local = completed(base)
    escaped = captureStorageHistory(local, limits).value
  assert escaped.storageHistoryAt(StorageHistoryIndex(0)).value.fact.copyStorageFactKey(ByteLimit(
      1)).value.len == 1
  assert escaped.storageHistorySource.value.completedSequenceInfo.value.entries == 1
  for i in 0..<25: discard captureStorageHistory(source,
      limits).value # Warm the exact immutable history retain/retire path.
  let before = getOccupiedMem()
  for i in 0..<1000: discard captureStorageHistory(source, limits).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("accumulation_storage_history", 1000, before, after)
  echo "accumulation-storage-history: ok"
try:
  main()
except:
  quit(2) # Source/setup refusal cannot masquerade as successful guard enforcement.
