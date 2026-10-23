# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Freeze bounded selected request identities from genuine completed current accumulation history; fixed facts preserve original producer positions without payload copying or hashing.
import ./[accumulation_current_driver, accumulation_current_sequence, accumulation_coverage,
    accumulation_annulment, accumulation_effects]
import ../codec/bounded
type
  RequestIdentityHistoryLimits* = object ## Original entries/outcomes, selected fixed facts and native row storage are independent policies.
    entries*, outcomes*, facts*: ElementLimit
    bytes*: ByteLimit
  RequestIdentityHistoryIndex* = distinct uint64 ## Flat selected request ordinal cannot substitute an entry or invocation index.
  RequestIdentityHistoryRow* = object ## Detached observations preserve original positions and fixed raw request identity; they cannot mutate history authority.
    entry*: CurrentSequenceEntryIndex
    outcome*: AccumulationAnnulmentIndex
    fact*: AccumulationRequestFact
  RequestIdentityHistoryInfo* = object ## Exact selected coverage remains separate from a complete logical manifest or last-value claim.
    entries*, outcomes*, facts*: int
    bytes*: uint64
  RequestIdentityHistory* = object ## Only complete original-source capture constructs immutable selected request history.
    initialized: bool
    source: CompletedCurrentAccumulationSequence
    rows: seq[RequestIdentityHistoryRow]
    info: RequestIdentityHistoryInfo
  RequestIdentityHistoryError* {.pure.} = enum ## Refused/default capture never treats absent producer policy as empty evidence.
    Uninitialized, None, InvalidSource, LimitExceeded, RequestFactsDisabled, InvalidIndex
  RequestIdentityHistoryResult*[T] = object ## Successful source-bound payloads stay private behind selected-stage access.
    case status: RequestIdentityHistoryError
    of None: completed: T
    else: discard # No successful prefix exists on any refused stage.
func error*[T](outcome: RequestIdentityHistoryResult[T]): RequestIdentityHistoryError =
  ## Observe immutable capture or lookup refusal.
  outcome.status
func value*[T](outcome: RequestIdentityHistoryResult[T]): T {.inline, requires: outcome.status ==
    RequestIdentityHistoryError.None.} =
  ## Extract only complete selected history and its bounded observations.
  outcome.completed
proc captureRequestIdentityHistory*(source: CompletedCurrentAccumulationSequence,
    limits: RequestIdentityHistoryLimits): RequestIdentityHistoryResult[RequestIdentityHistory] =
  ## Admit whole selected fixed-row retention before allocation, retaining original sequence and invocation provenance without re-execution.
  template fail(reason: RequestIdentityHistoryError) =
    return RequestIdentityHistoryResult[RequestIdentityHistory](status: reason)
  let info = source.completedSequenceInfo
  if info.error != CurrentSequenceDriverError.None: fail(RequestIdentityHistoryError.InvalidSource)
  if uint64(info.value.entries) > uint64(limits.entries): fail(
      RequestIdentityHistoryError.LimitExceeded)
  let sequence = source.completedSequenceSource.value
  let outcomeBudget = min(uint64(limits.outcomes), uint64(high(int)))
  let factBudget = min(uint64(limits.facts), uint64(high(int) div sizeof(
      RequestIdentityHistoryRow)))
  var outcomes = outcomeBudget
  var facts = factBudget
  for i in 0..<info.value.entries:
    # Original executed coverage counts even when every request fact is later cancelled.
    let selected = sequence.currentSequenceCoverageAt(CurrentSequenceEntryIndex(uint64(
        i))).value.coverageAnnulment.value
    let count = selected.annulmentInfo.value.outcomes
    if uint64(count) > outcomes: fail(RequestIdentityHistoryError.LimitExceeded)
    outcomes -= uint64(count)
    for j in 0..<count:
      let extent = selected.annulmentSelectedRequestFactCountAt(AccumulationAnnulmentIndex(uint64(j)))
      if extent.error == AccumulationAnnulmentError.RequestFactsDisabled:
        fail(RequestIdentityHistoryError.RequestFactsDisabled)
      if extent.error != AccumulationAnnulmentError.None: fail(
          RequestIdentityHistoryError.InvalidSource)
      if uint64(extent.value) > facts: fail(RequestIdentityHistoryError.LimitExceeded)
      facts -= uint64(extent.value)
  let count = factBudget-facts
  let bytes = min(uint64(limits.bytes), uint64(high(int)))
  if count > bytes div uint64(sizeof(RequestIdentityHistoryRow)):
    fail(RequestIdentityHistoryError.LimitExceeded) # Prove native extent, multiplication and the complete fixed-row ledger before allocation.
  var rows = newSeq[RequestIdentityHistoryRow](int(count))
  var next = 0
  for i in 0..<info.value.entries:
    # Actual entry order and original parallel invocation positions remain separate from host-operation ordering.
    let entry = CurrentSequenceEntryIndex(uint64(i))
    let selected = sequence.currentSequenceCoverageAt(entry).value.coverageAnnulment.value
    for j in 0..<selected.annulmentInfo.value.outcomes:
      let ordinal = AccumulationAnnulmentIndex(uint64(j))
      for k in 0..<selected.annulmentSelectedRequestFactCountAt(ordinal).value:
        rows[next] = RequestIdentityHistoryRow(entry: entry, outcome: ordinal,
            fact: selected.annulmentSelectedRequestFactAt(ordinal, AccumulationRequestFactIndex(
                uint64(k))).value)
        inc next # Complete preflight bounds every output ordinal.
  RequestIdentityHistoryResult[RequestIdentityHistory](status: RequestIdentityHistoryError.None,
      completed: RequestIdentityHistory(initialized: true, source: source, rows: rows,
          info: RequestIdentityHistoryInfo(entries: info.value.entries, outcomes: int(
              outcomeBudget-outcomes), facts: next, bytes: count*uint64(sizeof(
                  RequestIdentityHistoryRow)))))
proc requestIdentityHistoryInfo*(history: RequestIdentityHistory): RequestIdentityHistoryResult[
    RequestIdentityHistoryInfo] =
  ## Inspect exact complete selected coverage without granting a mutable row array.
  if not history.initialized:
    return RequestIdentityHistoryResult[RequestIdentityHistoryInfo](
        status: RequestIdentityHistoryError.InvalidSource)
  RequestIdentityHistoryResult[RequestIdentityHistoryInfo](status: RequestIdentityHistoryError.None,
      completed: history.info)
proc requestIdentityHistorySource*(history: RequestIdentityHistory): RequestIdentityHistoryResult[
    CompletedCurrentAccumulationSequence] =
  ## Retain only the original genuine completed producer for later exact-parent/successor composition.
  if not history.initialized:
    return RequestIdentityHistoryResult[CompletedCurrentAccumulationSequence](
        status: RequestIdentityHistoryError.InvalidSource)
  RequestIdentityHistoryResult[CompletedCurrentAccumulationSequence](
      status: RequestIdentityHistoryError.None, completed: history.source)
proc requestIdentityHistoryAt*(history: RequestIdentityHistory,
    index: RequestIdentityHistoryIndex): RequestIdentityHistoryResult[RequestIdentityHistoryRow] =
  ## Validate initialized source and complete full-width ordinal before returning a detached fixed row.
  if not history.initialized:
    return RequestIdentityHistoryResult[RequestIdentityHistoryRow](
        status: RequestIdentityHistoryError.InvalidSource)
  if uint64(index) >= uint64(history.rows.len):
    return RequestIdentityHistoryResult[RequestIdentityHistoryRow](
        status: RequestIdentityHistoryError.InvalidIndex)
  RequestIdentityHistoryResult[RequestIdentityHistoryRow](status: RequestIdentityHistoryError.None,
      completed: history.rows[int(uint64(index))])
