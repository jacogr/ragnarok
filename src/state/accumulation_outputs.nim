# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Collect terminal-selected output pairs from genuine completed accumulation rounds and retained history.
## Provides copied pairs, fresh log encoding and explicit history-root derivation without publishing state.

import std/algorithm
import ../codec/bounded as codec_bounded
import ../codec/composite as codec_composite
import ../codec/natural as codec_natural
import ../codec/state_outputs as codec_state_outputs
import ../codec/state_trie as codec_state_trie
import ./accumulation_execution as state_accumulation_execution
import ./accumulation_batch as state_accumulation_batch
import ./accumulation_outcome as state_accumulation_outcome
import ./accumulation_effects as state_accumulation_effects
import ./accumulation_provisions as state_accumulation_provisions
import ./accumulation_continuation_execution as state_accumulation_continuation_execution
import ./accumulation_continuation_inputs as state_accumulation_continuation_inputs
import ./accumulation_continuation as state_accumulation_continuation
import ./accumulation_reentry as state_accumulation_reentry
import ./history as state_history

type
  AccumulationOutputLimits* = object ## Traversal work is independent of retained pair count and canonical wire extent.
    executions*: ElementLimit ## Maximum executed outcomes inspected, including those without yields.
    log*: OutputLogConfig     ## Maximum retained output pairs and complete count-prefixed log bytes.
  AccumulationOutputHistoryLimits* = object ## Bound completed history separately from its deduplicated output set.
    rounds*: ElementLimit ## Maximum completed rounds inspected, including initial, continuation and idle terminal rounds.
    executions*: ElementLimit ## Maximum total executed outcomes inspected, including absent and duplicate yields.
    log*: OutputLogConfig ## Maximum unique pairs and complete count-prefixed log bytes; scratch rows use the execution ceiling.
  AccumulationOutputsInfo* = object ## Copied observations describe exactly the retained completed history, which may still be a block prefix.
    rounds*: int       ## Completed rounds included, counting idle rounds as traversal work.
    executions*: int   ## Total executed outcomes inspected, before absence filtering and pair deduplication.
    outputs*: int      ## Unique pairs ordered by numeric service, then lexicographic commitment bytes.
    encodedBytes*: int ## Exact C(16)-format extent, including the natural count prefix.
  AccumulationOutputsError* {.pure.} = enum ## Refusals expose no partial pairs, source certificate or encoded log.
    Uninitialized,  ## Default owner or result without completed output preparation.
    None,           ## Complete selected success permits guarded extraction.
    InvalidSource,  ## No genuine completed admitted round was supplied.
    NoContinuation, ## This projection contains only the initial round.
    NoReentry,      ## This projection contains no completed reentry.
    InvalidIndex,   ## The full-width output ordinal is outside the retained pairs.
    LimitExceeded,  ## Traversal, output count, native storage or canonical log bytes exceed local limits.
    HistoryFailure  ## Explicit root derivation refused; inspect its selected history reason.
  # Private acyclic storage retains the genuine completion and independent fixed output pairs.
  OutputsData = ref object
    source: CompletedBlockAccumulation
    continuation: CompletedAccumulationContinuation
    reentry: CompletedAccumulationReentry
    rounds, executions: int
    values: seq[AccumulationOutput]
    config: OutputLogConfig
    encodedBytes: int
  PreparedAccumulationOutputs* = object ## Only terminal-selected outcomes from a genuine completed source construct this immutable owner.
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

# Pair-set order compares numeric service first, then the fixed commitment octets lexicographically.
func compareOutput(left, right: AccumulationOutput): int =
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  let a = array[32, byte](left.commitment)
  let b = array[32, byte](right.commitment)
  for index in 0..<32:
    # Different commitments from the same service remain distinct set members.
    if a[index] < b[index]: return -1
    if a[index] > b[index]: return 1
  0

proc outputsInfo*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[
    AccumulationOutputsInfo] =
  ## Copy pair count and exact wire extent without exposing owned storage.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[AccumulationOutputsInfo](
        status: AccumulationOutputsError.Uninitialized) # Defaults are not initialized empty rounds.
  AccumulationOutputsResult[AccumulationOutputsInfo](status: AccumulationOutputsError.None,
    completed: AccumulationOutputsInfo(rounds: data.rounds, executions: data.executions,
      outputs: data.values.len, encodedBytes: data.encodedBytes))

proc outputsSource*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[
    CompletedBlockAccumulation] =
  ## Retain the initial admitted completion at the root of this projection's exact history.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[CompletedBlockAccumulation](
        status: AccumulationOutputsError.Uninitialized) # No synthetic execution or round provenance.
  AccumulationOutputsResult[CompletedBlockAccumulation](status: AccumulationOutputsError.None,
      completed: data.source)

proc outputsContinuation*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[
    CompletedAccumulationContinuation] =
  ## Retain the first continuation completion, or report NoContinuation for an initial-only projection.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[CompletedAccumulationContinuation](
      status: AccumulationOutputsError.Uninitialized) # Default owners carry no provenance.
  if data.rounds < 2:
    return AccumulationOutputsResult[CompletedAccumulationContinuation](
      status: AccumulationOutputsError.NoContinuation) # Absence is not a default successful completion.
  AccumulationOutputsResult[CompletedAccumulationContinuation](
    status: AccumulationOutputsError.None, completed: data.continuation)

proc outputsReentry*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[
    CompletedAccumulationReentry] =
  ## Retain the latest included reentry and its predecessor chain, or report NoReentry.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[CompletedAccumulationReentry](
      status: AccumulationOutputsError.Uninitialized) # A default projection has no completed tail.
  if data.rounds < 3:
    return AccumulationOutputsResult[CompletedAccumulationReentry](
      status: AccumulationOutputsError.NoReentry) # Initial and first continuation need no reentry owner.
  AccumulationOutputsResult[CompletedAccumulationReentry](status: AccumulationOutputsError.None,
    completed: data.reentry)

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
  ## Encode fresh independent C(16)-format bytes for the retained history; no state is published.
  let data = plan.data
  if data == nil:
    return AccumulationOutputsResult[StateEntry](status: AccumulationOutputsError.Uninitialized) # No encoding from a default owner.
  let encoded = outputLogEntry(data.values, data.config)
  if encoded.error != OutputLogError.None:
    return AccumulationOutputsResult[StateEntry](status: AccumulationOutputsError.LimitExceeded) # Preserve atomic refusal if codec extents cannot be represented.
  AccumulationOutputsResult[StateEntry](status: AccumulationOutputsError.None,
      completed: encoded.value)

proc outputsRoot*(plan: PreparedAccumulationOutputs): AccumulationOutputsResult[AccumulationRoot] =
  ## Explicitly derive the retained history's ordered root with the existing history algorithm; calls may hash and never publish state.
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
  let prefix = codec_natural.encode(JamNatural(present)).len
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
    completed: PreparedAccumulationOutputs(data: OutputsData(source: source, rounds: 1,
      executions: count, values: values,
      config: limits.log, encodedBytes: encodedBytes)))

# Bound every retained batch descriptor and aggregate outcome count before appending or inspecting outcomes.
proc appendBatch(batches: var seq[PreparedAccumulationBatch], executions: var uint64,
    batch: PreparedAccumulationBatch, limits: AccumulationOutputHistoryLimits): bool =
  let count = uint64(batch.batchInfo.value.executions)
  if uint64(batches.len) >= uint64(limits.rounds) or
      batches.len >= high(int) div sizeof(PreparedAccumulationBatch):
    return false # Idle rounds also consume work and native descriptor storage.
  if count > uint64(limits.executions) - executions or
      count > uint64(high(int) div sizeof(AccumulationOutput)) - executions:
    return false # Subtraction proves aggregate arithmetic and worst-case candidate storage.
  executions += count
  batches.add(batch)
  true

# Normalize only the mathematical pair union, never the already terminal-selected PVM outcomes.
proc collectHistory(batches: seq[PreparedAccumulationBatch], executions: uint64,
    source: CompletedBlockAccumulation, continuation: CompletedAccumulationContinuation,
    reentry: CompletedAccumulationReentry, config: OutputLogConfig):
    AccumulationOutputsResult[PreparedAccumulationOutputs] =
  template fail() =
    return AccumulationOutputsResult[PreparedAccumulationOutputs](
      status: AccumulationOutputsError.LimitExceeded)
  if uint64(config.maxBytes) < 1:
    fail() # Even an empty initialized log consumes a natural count byte.
  var present = 0
  for batch in batches:
    # The descriptor pass already bounded all rounds and outcomes before this presence scan.
    for index in 0..<batch.batchInfo.value.executions:
      if batch.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(
          index))).value.outcomeInfo.value.hasYield:
        inc present # Aggregate executions proves native count and typed scratch storage before allocation.
  if present > 0 and uint64(config.items) == 0:
    fail() # Nonempty presence cannot yield an empty pair union.
  var candidates = newSeq[AccumulationOutput](present)
  var cursor = 0
  for batch in batches:
    for index in 0..<batch.batchInfo.value.executions:
      # Preserve selected presence, including zero hashes, and every octet of the fixed commitment.
      let outcome = batch.batchOutcomeAt(AccumulationProvisionSourceIndex(uint64(index))).value
      let facts = outcome.outcomeInfo.value
      if facts.hasYield:
        candidates[cursor] = AccumulationOutput(service: facts.service,
          commitment: outcome.outcomeContext.value.effectYield.value)
        inc cursor
  candidates.sort(compareOutput)
  var unique = 0
  for index in 0..<candidates.len:
    # Compact adjacent equal pairs; neither service-only replacement nor hash-only deduplication is valid.
    if unique == 0 or compareOutput(candidates[index], candidates[unique-1]) != 0:
      if uint64(unique) >= uint64(config.items):
        fail() # The output ceiling applies to unique pairs, not repeated round yields.
      let candidate = candidates[index]
      candidates[unique] = candidate
      inc unique
  let prefix = codec_natural.encode(JamNatural(unique)).len
  if unique > (high(int)-prefix) div 36:
    fail() # Prove wire arithmetic independently of bounded candidate storage.
  let encodedBytes = prefix + unique*36
  if uint64(encodedBytes) > uint64(config.maxBytes):
    fail() # No oversized encoded payload or partially successful owner escapes.
  var values = newSeq[AccumulationOutput](unique)
  for index in 0..<unique:
    values[index] = candidates[index] # Retain only the bounded set, releasing duplicate scratch rows.
  AccumulationOutputsResult[PreparedAccumulationOutputs](status: AccumulationOutputsError.None,
    completed: PreparedAccumulationOutputs(data: OutputsData(source: source,
      continuation: continuation, reentry: reentry, rounds: batches.len, executions: int(
          executions),
      values: values, config: config, encodedBytes: encodedBytes)))

# Derive the first two rounds from one authenticated continuation, never from independently supplied batches.
proc appendInitial(batches: var seq[PreparedAccumulationBatch], executions: var uint64,
    source: CompletedAccumulationContinuation, limits: AccumulationOutputHistoryLimits): bool =
  let initial = source.executionContinuation.value.continuationPlan.value.continuationSource.value
  appendBatch(batches, executions, source.executionBatch.value, limits) and
    appendBatch(batches, executions, initial.executionBatch.value, limits)

proc prepareAccumulationOutputs*(source: CompletedAccumulationContinuation,
    limits: AccumulationOutputHistoryLimits): AccumulationOutputsResult[
        PreparedAccumulationOutputs] =
  ## Union the initial and first continuation's selected pairs under independent round/outcome/log ceilings.
  ## Scratch rows are bounded by executions; the unique set alone consumes the final log policy.
  if source.executionInfo.error != AccumulationContinuationExecutionError.None:
    return AccumulationOutputsResult[PreparedAccumulationOutputs](
      status: AccumulationOutputsError.InvalidSource) # A default certificate does not authorize an empty history.
  var batches: seq[PreparedAccumulationBatch] = @[]
  var executions = 0'u64
  if not appendInitial(batches, executions, source, limits):
    return AccumulationOutputsResult[PreparedAccumulationOutputs](
      status: AccumulationOutputsError.LimitExceeded) # No outcome traversal before complete history bounds.
  let initial = source.executionContinuation.value.continuationPlan.value.continuationSource.value
  collectHistory(batches, executions, initial, source, default(CompletedAccumulationReentry), limits.log)

proc prepareAccumulationOutputs*(source: CompletedAccumulationReentry,
    limits: AccumulationOutputHistoryLimits): AccumulationOutputsResult[
        PreparedAccumulationOutputs] =
  ## Union all retained initial/continuation/reentry rounds through this exact completion, without recursion.
  ## Partial histories remain projections; this does not certify accseq termination or publish C(16)/history.
  if source.executionInfo.error != AccumulationReentryExecutionError.None:
    return AccumulationOutputsResult[PreparedAccumulationOutputs](
      status: AccumulationOutputsError.InvalidSource) # No caller-authored batches, pairs or provenance are accepted.
  var batches: seq[PreparedAccumulationBatch] = @[]
  var executions = 0'u64
  var current = source
  while true:
    # The acyclic genuine predecessor chain is traversed iteratively under the explicit round ceiling.
    if not appendBatch(batches, executions, current.executionBatch.value, limits):
      return AccumulationOutputsResult[PreparedAccumulationOutputs](
        status: AccumulationOutputsError.LimitExceeded)
    let previous = current.executionReentry.value.reentryPrevious
    if previous.error == AccumulationReentryError.NoPrevious:
      break # Only the certified first reentry terminates this chain.
    current = previous.value
  let continuation = source.executionReentry.value.reentrySource.value
  if not appendInitial(batches, executions, continuation, limits):
    return AccumulationOutputsResult[PreparedAccumulationOutputs](
      status: AccumulationOutputsError.LimitExceeded) # Initial and continuation consume the same aggregate work limits.
  let initial = continuation.executionContinuation.value.continuationPlan.value.continuationSource.value
  collectHistory(batches, executions, initial, continuation, source, limits.log)
