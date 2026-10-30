# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Terminal current accseq output-pair union with explicit bounded C16 encoding and history-root derivation.
import std/algorithm
import ../../../codec/[bounded, natural]
import ../../../codec/state/[outputs as state_outputs, trie as state_trie]
import ./[driver as accumulation_current_driver, sequence as accumulation_current_sequence]
import ../annulled_outputs as accumulation_annulled_outputs
import ../../history

type
  CurrentAccumulationOutputLimits* = object ## Charge entry/outcome traversal independently of deduplicated pairs and canonical bytes.
    entries*, outcomes*: ElementLimit
    log*: OutputLogConfig
  CurrentAccumulationOutputsInfo* = object ## Original selected pair visits may exceed the complete retained pair set.
    entries*, outcomes*, visits*, outputs*, encodedBytes*: int
  CurrentAccumulationOutputsError* {.pure.} = enum ## Default/refused alternatives expose no earlier pair set or root.
    Uninitialized, None, InvalidSource, InvalidIndex, LimitExceeded, HistoryFailure
  CurrentOutputsData = ref object # Terminal source, fixed pair copies and frozen policy form an acyclic immutable owner.
    source: CompletedCurrentAccumulationSequence
    values: seq[AccumulationOutput]
    config: OutputLogConfig
    info: CurrentAccumulationOutputsInfo
  PreparedCurrentAccumulationOutputs* = object ## Only terminal current sequence ownership authorizes this complete selected output union.
    data: nil CurrentOutputsData
  CurrentAccumulationOutputsResult*[T] = object ## Private selected alternatives permit extraction only after complete success.
    case status: CurrentAccumulationOutputsError
    of None:
      completed: T
    of HistoryFailure:
      historyReason: HistoryTransitionError
    else:
      discard # No partial pairs, candidate root or successful prefix survives refusal.

func error*[T](outcome: CurrentAccumulationOutputsResult[T]): CurrentAccumulationOutputsError =
  ## Inspect only the selected immutable reason.
  outcome.status

func value*[T](outcome: CurrentAccumulationOutputsResult[T]): T {.inline,
    requires: outcome.status == CurrentAccumulationOutputsError.None.} =
  ## Extract only complete selected values and immutable owners.
  outcome.completed

func historyFailure*[T](outcome: CurrentAccumulationOutputsResult[
    T]): HistoryTransitionError {.inline,

requires: outcome.status == CurrentAccumulationOutputsError.HistoryFailure.} =
  ## Inspect only an actual explicit root-derivation refusal.
  outcome.historyReason

func comparePair(left, right: AccumulationOutput): int =
  ## Numeric service then lexicographic commitment preserves distinct outputs from the same service.
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  let a = array[32, byte](left.commitment)
  let b = array[32, byte](right.commitment)
  for index in 0..<32:
    if a[index] < b[index]: return -1 # Fixed byte order is independent of native integer endianness.
    if a[index] > b[index]: return 1 # Pair equality requires both identity and every commitment octet.
  0

proc prepareCurrentAccumulationOutputs*(source: CompletedCurrentAccumulationSequence,
    limits: CurrentAccumulationOutputLimits): CurrentAccumulationOutputsResult[
        PreparedCurrentAccumulationOutputs] =
  ## Preflight complete traversal and scratch extents; collect genuine selected pairs without re-normalizing original executions.
  template fail(reason: CurrentAccumulationOutputsError) =
    return CurrentAccumulationOutputsResult[PreparedCurrentAccumulationOutputs](status: reason)
  let sequence = source.completedSequenceSource
  if sequence.error != CurrentSequenceDriverError.None:
    fail(CurrentAccumulationOutputsError.InvalidSource) # Active/default/pure sources cannot authorize a terminal log.
  let entries = sequence.value.currentSequenceInfo.value.entries
  if uint64(entries) > uint64(limits.entries) or uint64(limits.log.maxBytes) < 1:
    fail(CurrentAccumulationOutputsError.LimitExceeded) # Even an initialized empty log requires its count byte.
  var outcomes = 0'u64
  var present = 0
  let nativeRows = uint64(high(int) div sizeof(AccumulationOutput))
  for ordinal in 0..<entries:
    let info = sequence.value.currentSequenceOutputsAt(CurrentSequenceEntryIndex(uint64(
        ordinal))).value.annulmentOutputsInfo.value
    let count = uint64(info.outcomes)
    if outcomes > uint64(limits.outcomes) or count > uint64(limits.outcomes)-outcomes or
        outcomes > nativeRows or count > nativeRows-outcomes:
      fail(CurrentAccumulationOutputsError.LimitExceeded) # Bound original canceled/absent-yield visits before any candidate allocation.
    outcomes += count
    present += info.outputs # Genuine selected pairs are a subset of the preflighted original outcomes.
  if present > 0 and uint64(limits.log.items) == 0:
    fail(CurrentAccumulationOutputsError.LimitExceeded) # Nonempty selected presence cannot have an empty pair union.
  var candidates = newSeq[AccumulationOutput](present)
  var cursor = 0
  for ordinal in 0..<entries:
    let outputs = sequence.value.currentSequenceOutputsAt(CurrentSequenceEntryIndex(uint64(
        ordinal))).value
    for index in 0..<outputs.annulmentOutputsInfo.value.outputs:
      candidates[cursor] = outputs.annulmentOutputAt(AnnulmentOutputIndex(uint64(index))).value
      inc cursor # The frozen selected count proves each copied candidate slot.
  candidates.sort(comparePair)
  var unique = 0
  for index in 0..<candidates.len:
    if unique == 0 or comparePair(candidates[index], candidates[unique-1]) != 0:
      if uint64(unique) >= uint64(limits.log.items):
        fail(CurrentAccumulationOutputsError.LimitExceeded) # Apply retained capacity after full-pair deduplication, never service-only replacement.
      let candidate = candidates[index]
      candidates[unique] = candidate
      inc unique # Read the original row before compacting its earlier slot.
  let prefix = int(natural.encode(JamNatural(unique)).len)
  if unique > (high(int)-prefix) div 36:
    fail(CurrentAccumulationOutputsError.LimitExceeded) # Prove complete encoded arithmetic before multiplication.
  let encodedBytes = prefix+36*unique
  if uint64(encodedBytes) > uint64(limits.log.maxBytes):
    fail(CurrentAccumulationOutputsError.LimitExceeded) # No oversized complete wire or earlier prefix escapes.
  var values = newSeq[AccumulationOutput](unique)
  for index in 0..<unique:
    values[index] = candidates[index] # Retain only the bounded mathematical set, releasing duplicate scratch storage.
  CurrentAccumulationOutputsResult[PreparedCurrentAccumulationOutputs](
    status: CurrentAccumulationOutputsError.None,
    completed: PreparedCurrentAccumulationOutputs(data: CurrentOutputsData(source: source,
      values: values,
      config: limits.log, info: CurrentAccumulationOutputsInfo(entries: entries, outcomes: int(
          outcomes),
        visits: present, outputs: unique, encodedBytes: encodedBytes))))

proc currentOutputsInfo*(outputs: PreparedCurrentAccumulationOutputs): CurrentAccumulationOutputsResult[
    CurrentAccumulationOutputsInfo] =
  ## Copy complete observations without exposing mutable pair storage.
  let data = outputs.data
  if data == nil: return CurrentAccumulationOutputsResult[CurrentAccumulationOutputsInfo](
      status: CurrentAccumulationOutputsError.Uninitialized) # Defaults have no log observations.
  CurrentAccumulationOutputsResult[CurrentAccumulationOutputsInfo](
      status: CurrentAccumulationOutputsError.None, completed: data.info)

proc currentOutputsSource*(outputs: PreparedCurrentAccumulationOutputs): CurrentAccumulationOutputsResult[
    CompletedCurrentAccumulationSequence] =
  ## Retain the exact terminal current sequence independently of caller handles.
  let data = outputs.data
  if data == nil: return CurrentAccumulationOutputsResult[CompletedCurrentAccumulationSequence](
      status: CurrentAccumulationOutputsError.Uninitialized) # No synthetic terminal provenance.
  CurrentAccumulationOutputsResult[CompletedCurrentAccumulationSequence](
      status: CurrentAccumulationOutputsError.None, completed: data.source)

proc currentOutputAt*(outputs: PreparedCurrentAccumulationOutputs,
    index: OutputLogIndex): CurrentAccumulationOutputsResult[AccumulationOutput] =
  ## Extract an independent fixed pair after full-width ordinal validation.
  let data = outputs.data
  if data == nil: return CurrentAccumulationOutputsResult[AccumulationOutput](
      status: CurrentAccumulationOutputsError.Uninitialized) # No fabricated zero pair.
  if uint64(index) >= uint64(data.values.len): return CurrentAccumulationOutputsResult[
      AccumulationOutput](
      status: CurrentAccumulationOutputsError.InvalidIndex) # Prove narrowing and access before reading storage.
  CurrentAccumulationOutputsResult[AccumulationOutput](status: CurrentAccumulationOutputsError.None,
      completed: data.values[int(uint64(index))])

proc currentOutputsEntry*(outputs: PreparedCurrentAccumulationOutputs): CurrentAccumulationOutputsResult[StateEntry] =
  ## Encode fresh independent C16 bytes; this projection publishes no state.
  let data = outputs.data
  if data == nil: return CurrentAccumulationOutputsResult[StateEntry](
      status: CurrentAccumulationOutputsError.Uninitialized) # Defaults cannot encode an initialized empty log.
  let encoded = outputLogEntry(data.values, data.config)
  if encoded.error != OutputLogError.None: return CurrentAccumulationOutputsResult[StateEntry](
      status: CurrentAccumulationOutputsError.LimitExceeded) # Retain complete codec refusal atomically.
  CurrentAccumulationOutputsResult[StateEntry](status: CurrentAccumulationOutputsError.None,
      completed: encoded.value)

proc currentOutputsRoot*(outputs: PreparedCurrentAccumulationOutputs): CurrentAccumulationOutputsResult[
    AccumulationRoot] =
  ## Explicitly hash the complete selected union through the existing well-balanced history primitive.
  let data = outputs.data
  if data == nil: return CurrentAccumulationOutputsResult[AccumulationRoot](
      status: CurrentAccumulationOutputsError.Uninitialized) # No fabricated root from a default owner.
  let rooted = accumulationRoot(data.values, data.config)
  if rooted.error != HistoryTransitionError.None:
    return CurrentAccumulationOutputsResult[AccumulationRoot](
        status: CurrentAccumulationOutputsError.HistoryFailure,
        historyReason: rooted.error) # Preserve the actual history/backend refusal.
  CurrentAccumulationOutputsResult[AccumulationRoot](status: CurrentAccumulationOutputsError.None,
      completed: rooted.value)
