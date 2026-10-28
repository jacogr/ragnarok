# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Collect bounded producer-owned storage identities from every selected invocation in a genuine completed current sequence, preserving actual entry provenance and annulment decisions.
import ./accumulation_current_driver as state_accumulation_current_driver
import ./accumulation_current_sequence as state_accumulation_current_sequence
import ./accumulation_coverage as state_accumulation_coverage
import ./accumulation_annulment as state_accumulation_annulment
import ./accumulation_effects as state_accumulation_effects
import ../codec/bounded as codec_bounded
type
  StorageHistoryLimits* = object ## Whole entry/outcome traversal and retained fact descriptors/raw bytes have independent ceilings.
    entries*, outcomes*, facts*: ElementLimit
    bytes*: ByteLimit
  StorageHistoryIndex* = distinct uint64 ## Flat selected storage ordinal is distinct from entry, invocation and per-context fact indices.
  StorageHistoryRow* = object ## Copied observation names original producer positions; mutating it cannot alter retained history.
    entry*: CurrentSequenceEntryIndex
    outcome*: AccumulationAnnulmentIndex
    fact*: AccumulationStorageFact
  StorageHistoryInfo* = object ## Actual selected coverage counts do not claim a complete logical namespace or whole-block mutation manifest.
    entries*, outcomes*, facts*: int
    bytes*: uint64
  StorageHistory* = object ## Only complete bounded original-source capture creates immutable selected identity history.
    initialized: bool
    source: CompletedCurrentAccumulationSequence
    rows: seq[StorageHistoryRow]
    info: StorageHistoryInfo
  StorageHistoryError* {.pure.} = enum ## No failure exposes an admitted prefix or guesses that disabled capture was empty.
    Uninitialized, None, InvalidSource, LimitExceeded, StorageFactsDisabled, InvalidIndex
  StorageHistoryResult*[T] = object ## Private successful payloads remain inaccessible on defaults and every refused stage.
    case status: StorageHistoryError
    of None: completed: T
    else: discard # There is no successful partial history alternative.
func error*[T](outcome: StorageHistoryResult[T]): StorageHistoryError =
  ## Inspect immutable capture or observation refusal.
  outcome.status
func value*[T](outcome: StorageHistoryResult[T]): T {.inline, requires: outcome.status ==
    StorageHistoryError.None.} =
  ## Extract only complete source-bound selected evidence or its detached fixed observations.
  outcome.completed
proc captureStorageHistory*(source: CompletedCurrentAccumulationSequence,
    limits: StorageHistoryLimits): StorageHistoryResult[StorageHistory] =
  ## Traverse authentic current history twice: first admit every selected identity, then retain exact immutable facts without copying raw bytes or hashing.
  template fail(reason: StorageHistoryError) =
    return StorageHistoryResult[StorageHistory](status: reason)
  let info = source.completedSequenceInfo
  if info.error != CurrentSequenceDriverError.None: fail(StorageHistoryError.InvalidSource)
  if uint64(info.value.entries) > uint64(limits.entries): fail(StorageHistoryError.LimitExceeded)
  let sequence = source.completedSequenceSource.value
  let outcomeBudget = min(uint64(limits.outcomes), uint64(high(int)))
  var outcomes = outcomeBudget
  var facts = min(uint64(limits.facts), uint64(high(int) div sizeof(StorageHistoryRow)))
  let factBudget = facts
  var bytes = min(uint64(limits.bytes), uint64(high(int)))
  let byteBudget = bytes
  for i in 0..<info.value.entries:
    # Charge complete original invocation coverage even when all its identities are later annulled.
    let coverage = sequence.currentSequenceCoverageAt(CurrentSequenceEntryIndex(uint64(i))).value
    let selected = coverage.coverageAnnulment.value
    let count = selected.annulmentInfo.value.outcomes
    if uint64(count) > outcomes: fail(StorageHistoryError.LimitExceeded)
    outcomes -= uint64(count)
    for j in 0..<count:
      let ordinal = AccumulationAnnulmentIndex(uint64(j))
      let extent = selected.annulmentSelectedStorageFactCountAt(ordinal)
      if extent.error == AccumulationAnnulmentError.StorageFactsDisabled:
        fail(StorageHistoryError.StorageFactsDisabled) # No enabled empty trace is inferred from a missing producer policy.
      if extent.error != AccumulationAnnulmentError.None: fail(StorageHistoryError.InvalidSource)
      if uint64(extent.value) > facts: fail(StorageHistoryError.LimitExceeded)
      facts -= uint64(extent.value)
      for k in 0..<extent.value:
        # Exact descriptor and logical retained raw-byte charges precede all output allocation.
        let fact = selected.annulmentSelectedStorageFactAt(ordinal, AccumulationStorageFactIndex(
            uint64(k))).value
        if bytes < uint64(sizeof(StorageHistoryRow)): fail(StorageHistoryError.LimitExceeded)
        bytes -= uint64(sizeof(StorageHistoryRow))
        let size = uint64(fact.storageFactInfo.value.rawBytes)
        if size > bytes: fail(StorageHistoryError.LimitExceeded)
        bytes -= size
  var rows = newSeq[StorageHistoryRow](int(factBudget-facts))
  var next = 0
  for i in 0..<info.value.entries:
    # Preserve entry order and original parallel-outcome positions without inventing a global host-operation order.
    let entry = CurrentSequenceEntryIndex(uint64(i))
    let selected = sequence.currentSequenceCoverageAt(entry).value.coverageAnnulment.value
    for j in 0..<selected.annulmentInfo.value.outcomes:
      let ordinal = AccumulationAnnulmentIndex(uint64(j))
      for k in 0..<selected.annulmentSelectedStorageFactCountAt(ordinal).value:
        rows[next] = StorageHistoryRow(entry: entry, outcome: ordinal,
            fact: selected.annulmentSelectedStorageFactAt(ordinal, AccumulationStorageFactIndex(
                uint64(k))).value)
        inc next # Complete preflight bounds the signed output ordinal before each assignment.
  StorageHistoryResult[StorageHistory](status: StorageHistoryError.None,
      completed: StorageHistory(initialized: true, source: source, rows: rows,
          info: StorageHistoryInfo(entries: info.value.entries, outcomes: int(
              outcomeBudget-outcomes), facts: next, bytes: byteBudget-bytes)))
proc storageHistoryInfo*(history: StorageHistory): StorageHistoryResult[StorageHistoryInfo] =
  ## Observe only initialized complete-capture coverage and exact admitted retention accounting.
  if not history.initialized:
    return StorageHistoryResult[StorageHistoryInfo](status: StorageHistoryError.InvalidSource)
  StorageHistoryResult[StorageHistoryInfo](status: StorageHistoryError.None,
      completed: history.info)
proc storageHistorySource*(history: StorageHistory): StorageHistoryResult[
    CompletedCurrentAccumulationSequence] =
  ## Retain original completed producer history for subsequent exact-parent/successor checks; roots alone cannot replace it.
  if not history.initialized:
    return StorageHistoryResult[CompletedCurrentAccumulationSequence](
        status: StorageHistoryError.InvalidSource)
  StorageHistoryResult[CompletedCurrentAccumulationSequence](status: StorageHistoryError.None,
      completed: history.source)
proc storageHistoryAt*(history: StorageHistory, index: StorageHistoryIndex): StorageHistoryResult[
    StorageHistoryRow] =
  ## Return one detached row retaining its immutable genuine raw identity, after full-width index validation.
  if not history.initialized:
    return StorageHistoryResult[StorageHistoryRow](status: StorageHistoryError.InvalidSource)
  if uint64(index) >= uint64(history.rows.len):
    return StorageHistoryResult[StorageHistoryRow](status: StorageHistoryError.InvalidIndex)
  StorageHistoryResult[StorageHistoryRow](status: StorageHistoryError.None, completed: history.rows[
      int(uint64(index))])
