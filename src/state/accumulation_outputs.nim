# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Collect terminal-selected service/output pairs from one genuine completed initial accumulation round.
## Provides copied pairs, fresh log encoding and explicit history-root derivation without publishing state.

import std/algorithm
import ../codec/[bounded, composite, natural, state_outputs, state_trie]
import ./[accumulation_execution, accumulation_batch, accumulation_outcome, accumulation_effects,
  accumulation_provisions, history]

type
  AccumulationOutputLimits* = object ## Traversal work is independent of retained pair count and canonical wire extent.
    executions*: ElementLimit ## Maximum executed outcomes inspected, including those without yields.
    log*: OutputLogConfig     ## Maximum retained output pairs and complete count-prefixed log bytes.
  AccumulationOutputsInfo* = object ## Copied observations describe this round's output projection, not a final block log.
    outputs*: int      ## Present service/output pairs, sorted numerically by unique service.
    encodedBytes*: int ## Exact one-round C(16)-format extent, including the natural count prefix.
  AccumulationOutputsError* {.pure.} = enum ## Refusals expose no partial pairs, source certificate or encoded log.
    Uninitialized, ## Default owner or result without completed output preparation.
    None,          ## Complete selected success permits guarded extraction.
    InvalidSource, ## No genuine completed admitted round was supplied.
    InvalidIndex,  ## The full-width output ordinal is outside the retained pairs.
    LimitExceeded, ## Traversal, output count, native storage or canonical log bytes exceed local limits.
    HistoryFailure ## Explicit root derivation refused; inspect its selected history reason.
  # Private acyclic storage retains the genuine completion and independent fixed output pairs.
  OutputsData = ref object
    source: CompletedBlockAccumulation
    values: seq[AccumulationOutput]
    config: OutputLogConfig
    encodedBytes: int
  PreparedAccumulationOutputs* = object ## Only terminal-selected outcomes of a completed admitted round construct this immutable owner.
    data: nil OutputsData
  AccumulationOutputsResult*[T] = object ## Defaults and refusals retain reasons alone, never an earlier successful candidate.
    case status: AccumulationOutputsError
    of None:
      completed: T # Only selected complete success exposes immutable handles or independent value copies.
    of HistoryFailure:
      historyReason: HistoryTransitionError
    else:
      discard # No fabricated empty output sequence or default root is carried on failure.

func error*[T](outcome: AccumulationOutputsResult[T]): AccumulationOutputsError =
  ## Inspect the selected reason without exposing a writable tag.
  outcome.status

func value*[T](outcome: AccumulationOutputsResult[T]): T {.inline,
    requires: outcome.status == AccumulationOutputsError.None.} =
  ## Extract selected success under checked optimized contracts.
  outcome.completed

func historyError*[T](outcome: AccumulationOutputsResult[T]): HistoryTransitionError {.inline,
    requires: outcome.status == AccumulationOutputsError.HistoryFailure.} =
  ## Inspect only an actual refusal from explicit history-root derivation.
  outcome.historyReason

# Unique service membership was established by the completed batch; commitments need no tie-breaker here.
func compareOutput(left, right: AccumulationOutput): int =
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  0

proc outputsInfo*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[
    AccumulationOutputsInfo] =
  ## Copy pair count and exact wire extent without exposing owned storage.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[AccumulationOutputsInfo](
        status: AccumulationOutputsError.Uninitialized) # Defaults are not initialized empty rounds.
  AccumulationOutputsResult[AccumulationOutputsInfo](status: AccumulationOutputsError.None,
    completed: AccumulationOutputsInfo(outputs: data.values.len, encodedBytes: data.encodedBytes))

proc outputsSource*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[
    CompletedBlockAccumulation] =
  ## Retain the exact admitted completion independently of this output projection's lifetime.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[CompletedBlockAccumulation](
        status: AccumulationOutputsError.Uninitialized) # No synthetic execution or round provenance.
  AccumulationOutputsResult[CompletedBlockAccumulation](status: AccumulationOutputsError.None,
      completed: data.source)

proc outputAt*(plan: PreparedAccumulationOutputs, index: OutputLogIndex): AccumulationOutputsResult[
    AccumulationOutput] =
  ## Copy a pair at its sorted output ordinal; no absent yield is represented as an all-zero pair.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[AccumulationOutput](
        status: AccumulationOutputsError.Uninitialized) # No default output record.
  if uint64(index) >= uint64(data.values.len):
    return AccumulationOutputsResult[AccumulationOutput](
        status: AccumulationOutputsError.InvalidIndex) # Full-width bounds precede narrowing.
  AccumulationOutputsResult[AccumulationOutput](status: AccumulationOutputsError.None,
      completed: data.values[int(uint64(index))])

proc outputsEntry*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[StateEntry] =
  ## Encode fresh independent one-round C(16)-format bytes; this does not publish a final block log.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[StateEntry](status: AccumulationOutputsError.Uninitialized) # No encoding from a default owner.
  let encoded = outputLogEntry(data.values, data.config)
  if encoded.error != OutputLogError.None:
    return AccumulationOutputsResult[StateEntry](status: AccumulationOutputsError.LimitExceeded) # Preserve atomic refusal if codec extents cannot be represented.
  AccumulationOutputsResult[StateEntry](status: AccumulationOutputsError.None,
      completed: encoded.value)

proc outputsRoot*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[AccumulationRoot] =
  ## Explicitly derive this round's ordered root with the existing history algorithm; calls may hash and never publish state.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[AccumulationRoot](
        status: AccumulationOutputsError.Uninitialized) # Default owners cannot supply a fake zero root.
  let rooted = accumulationRoot(data.values, data.config)
  if rooted.error != HistoryTransitionError.None:
    return AccumulationOutputsResult[AccumulationRoot](
      status: AccumulationOutputsError.HistoryFailure,
      historyReason: rooted.error) # No candidate root escapes backend or extent refusal.
  AccumulationOutputsResult[AccumulationRoot](status: AccumulationOutputsError.None,
      completed: rooted.value)

proc prepareAccumulationOutputs*(source: CompletedBlockAccumulation,
    limits: AccumulationOutputLimits):
    AccumulationOutputsResult[PreparedAccumulationOutputs] =
  ## Capture present terminal-selected yields in numeric service order, preserving the genuine admitted source.
  ## Traversal/count/wire preflight precedes allocation; preparation neither hashes nor re-normalizes executions.
  # Refuse before retaining any partial pair set or earlier source projection.
  template fail(reason: AccumulationOutputsError) =
    return AccumulationOutputsResult[PreparedAccumulationOutputs](status: reason)
  let info = source.executionInfo
  if info.error != AccumulationExecutionError.None:
    fail(AccumulationOutputsError.InvalidSource) # A default completion cannot stand for empty execution.
  let count = info.value.batch.executions
  if uint64(count) > uint64(limits.executions):
    fail(AccumulationOutputsError.LimitExceeded) # Even absent yields require bounded outcome traversal.
  let batch = source.executionBatch.value
  var present = 0
  for index in 0..<count:
    # Count only genuine normalized presence, including an actual all-zero commitment.
    let outcome = batch.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
    if outcome.outcomeInfo.value.hasYield:
      if uint64(present) >= uint64(limits.log.items):
        fail(AccumulationOutputsError.LimitExceeded) # Count increment is bounded by the already bounded execution count.
      inc present
  let prefix = natural.encode(JamNatural(present)).len
  if present > (high(int) - prefix) div 36 or present > high(int) div sizeof(AccumulationOutput):
    fail(AccumulationOutputsError.LimitExceeded) # Prove both native row storage and full wire arithmetic first.
  let encodedBytes = prefix + present * 36
  if uint64(encodedBytes) > uint64(limits.log.maxBytes):
    fail(AccumulationOutputsError.LimitExceeded) # An initialized empty log still requires its canonical count byte.
  var values = newSeq[AccumulationOutput](present)
  var cursor = 0
  for index in 0..<count:
    # The selected context already incorporates checkpoint rollback and any readable 32-byte halt override.
    let outcome = batch.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
    let facts = outcome.outcomeInfo.value
    if facts.hasYield:
      values[cursor] = AccumulationOutput(service: facts.service,
          commitment: outcome.outcomeContext.value.effectYield.value)
      inc cursor
  values.sort(compareOutput)
  AccumulationOutputsResult[PreparedAccumulationOutputs](status: AccumulationOutputsError.None,
    completed: PreparedAccumulationOutputs(data: OutputsData(source: source, values: values,
      config: limits.log, encodedBytes: encodedBytes)))
