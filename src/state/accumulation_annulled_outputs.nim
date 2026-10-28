# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current accpar service/yield pairs bound to genuine conflict-annulment decisions.
## This separate owner cannot impersonate a completed round/history or final block output certificate.
import std/algorithm
import ../codec/bounded as codec_bounded
import ../codec/natural as codec_natural
import ../codec/state_outputs as codec_state_outputs
import ../codec/state_trie as codec_state_trie
import ./accumulation_annulment as state_accumulation_annulment
import ./accumulation_outcome as state_accumulation_outcome
import ./accumulation_effects as state_accumulation_effects

type
  AnnulmentOutputIndex* = distinct uint64 ## Output-pair ordinal cannot substitute a service or source-outcome ordinal.
  AnnulmentOutputLimits* = object ## Original outcome traversal and complete encoded selected output have independent ceilings.
    outcomes*: ElementLimit ## Count canceled and absent-yield producers too.
    log*: OutputLogConfig   ## Count selected pairs and whole canonical count-prefixed bytes.
  AnnulmentOutputsInfo* = object ## Copied observations describe one parallel-entry projection, not final block history.
    outcomes*, outputs*, encodedBytes*: int ## Actual source traversal, present pair count and canonical wire extent.
  AnnulmentOutputsError* {.pure.} = enum ## Failed/default alternatives carry no pair set, source or encoded output.
    Uninitialized, None, InvalidSource, InvalidIndex, LimitExceeded
  AnnulmentOutputsData = ref object # Fixed independent pairs and genuine immutable source owner form an acyclic graph.
    source: PreparedAccumulationAnnulment
    values: seq[AccumulationOutput]
    config: OutputLogConfig
    info: AnnulmentOutputsInfo
  PreparedAnnulmentOutputs* = object ## Successful checked preparation alone constructs a retained selected pair set.
    data: nil AnnulmentOutputsData
  AnnulmentOutputsResult*[T] = object ## Read-only selected success guards all payload extraction.
    case status: AnnulmentOutputsError
    of None:
      completed: T                    # No public tag or inactive payload storage.
    else:
      discard                         # Refusal retains only its reason.

func error*[T](outcome: AnnulmentOutputsResult[T]): AnnulmentOutputsError =
  ## Inspect the selected reason without permitting retagging.
  outcome.status
func value*[T](outcome: AnnulmentOutputsResult[T]): T {.inline,
    requires: outcome.status == AnnulmentOutputsError.None.} =
  ## Extract complete selected success under checked optimized contracts.
  outcome.completed
func comparePair(left, right: AccumulationOutput): int =
  ## Preserve the established pair-set order; genuine unique sources permit only one commitment per service here.
  if uint32(left.service) < uint32(right.service): return -1
  if uint32(left.service) > uint32(right.service): return 1
  let a = array[32, byte](left.commitment)
  let b = array[32, byte](right.commitment)
  for index in 0..<32:
    if a[index] < b[index]: return -1 # Fixed lexicographic octet order, never host-endian integer order.
    if a[index] > b[index]: return 1 # Complete equality is not an absent yield sentinel.
  0

proc prepareAnnulmentOutputs*(source: PreparedAccumulationAnnulment,
    limits: AnnulmentOutputLimits): AnnulmentOutputsResult[PreparedAnnulmentOutputs] =
  ## Count selected presence and prove every native/wire extent before copying complete fixed commitments.
  template fail(reason: AnnulmentOutputsError) =
    return AnnulmentOutputsResult[PreparedAnnulmentOutputs](status: reason)
  let facts = source.annulmentInfo
  if facts.error != AccumulationAnnulmentError.None:
    fail(AnnulmentOutputsError.InvalidSource) # No fabricated empty or caller-authored selection certificate.
  let outcomes = facts.value.outcomes
  if uint64(outcomes) > uint64(limits.outcomes):
    fail(AnnulmentOutputsError.LimitExceeded) # Canceled and absent-yield originals still consume bounded inspection work.
  var present = 0
  for index in 0..<outcomes:
    let info = source.annulmentSelectedInfoAt(AccumulationAnnulmentIndex(uint64(index))).value
    if info.hasYield:
      if uint64(present) >= uint64(limits.log.items):
        fail(AnnulmentOutputsError.LimitExceeded) # Charge the next selected pair before incrementing or allocation.
      inc present # Presence is explicit even when every commitment byte is zero.
  let prefix = int(codec_natural.encode(JamNatural(present)).len)
  if present > (high(int)-prefix) div 36 or present > high(int) div sizeof(AccumulationOutput):
    fail(AnnulmentOutputsError.LimitExceeded) # Prove both complete encoded bytes and typed native storage before multiplication.
  let bytes = prefix+present*36
  if uint64(bytes) > uint64(limits.log.maxBytes):
    fail(AnnulmentOutputsError.LimitExceeded) # Empty selected output still needs its canonical count prefix.
  var values = newSeq[AccumulationOutput](present)
  var cursor = 0
  for index in 0..<outcomes:
    let ordinal = AccumulationAnnulmentIndex(uint64(index))
    let info = source.annulmentSelectedInfoAt(ordinal).value
    if info.hasYield:
      let original = source.annulmentOriginalOutcomeAt(ordinal).value
      let commitment = original.outcomeContext.value.effectYield.value
      values[cursor] = AccumulationOutput(service: info.service, commitment: commitment)
      inc cursor # Frozen selected cardinality proves every fixed pair slot is in range.
  values.sort(comparePair)
  AnnulmentOutputsResult[PreparedAnnulmentOutputs](status: AnnulmentOutputsError.None,
    completed: PreparedAnnulmentOutputs(data: AnnulmentOutputsData(source: source, values: values,
      config: limits.log, info: AnnulmentOutputsInfo(outcomes: outcomes, outputs: present,
          encodedBytes: bytes))))

proc annulmentOutputsInfo*(plan: PreparedAnnulmentOutputs): AnnulmentOutputsResult[
    AnnulmentOutputsInfo] =
  ## Copy selected cardinalities/extent without exposing mutable pair storage.
  let data = plan.data
  if data == nil: return AnnulmentOutputsResult[AnnulmentOutputsInfo](
      status: AnnulmentOutputsError.Uninitialized) # No fabricated empty projection.
  AnnulmentOutputsResult[AnnulmentOutputsInfo](status: AnnulmentOutputsError.None,
      completed: data.info)
proc annulmentOutputsSource*(plan: PreparedAnnulmentOutputs): AnnulmentOutputsResult[
    PreparedAccumulationAnnulment] =
  ## Retain the exact genuine conflict decisions that authorized pair presence.
  let data = plan.data
  if data == nil: return AnnulmentOutputsResult[PreparedAccumulationAnnulment](
      status: AnnulmentOutputsError.Uninitialized) # Default owners have no source.
  AnnulmentOutputsResult[PreparedAccumulationAnnulment](status: AnnulmentOutputsError.None,
      completed: data.source)
proc annulmentOutputAt*(plan: PreparedAnnulmentOutputs,
    index: AnnulmentOutputIndex): AnnulmentOutputsResult[AccumulationOutput] =
  ## Copy a complete service/hash pair after a full-width bound check, preserving real zero commitments.
  let data = plan.data
  if data == nil: return AnnulmentOutputsResult[AccumulationOutput](
      status: AnnulmentOutputsError.Uninitialized) # No default pair.
  if uint64(index) >= uint64(data.values.len): return AnnulmentOutputsResult[AccumulationOutput](
      status: AnnulmentOutputsError.InvalidIndex) # Upper bits never alias an existing ordinal.
  AnnulmentOutputsResult[AccumulationOutput](status: AnnulmentOutputsError.None,
      completed: data.values[int(uint64(index))])
proc annulmentOutputsEntry*(plan: PreparedAnnulmentOutputs): AnnulmentOutputsResult[StateEntry] =
  ## Encode fresh C(16)-format bytes for this selected set; no state store or final block output is published.
  let data = plan.data
  if data == nil: return AnnulmentOutputsResult[StateEntry](
      status: AnnulmentOutputsError.Uninitialized) # Defaults cannot encode a false empty output log.
  let encoded = outputLogEntry(data.values, data.config)
  if encoded.error != OutputLogError.None:
    return AnnulmentOutputsResult[StateEntry](status: AnnulmentOutputsError.LimitExceeded) # Frozen extent/config proofs keep canonical encoder refusal atomic.
  AnnulmentOutputsResult[StateEntry](status: AnnulmentOutputsError.None, completed: encoded.value)
