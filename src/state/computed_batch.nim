# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compose verified computed guarantees only within one exact authenticated execution context.

import ../chain/parameters as chain_parameters
import ../codec/bounded as codec_bounded
import ../codec/assurances as codec_assurances
import ../codec/guarantees as codec_guarantees
import ../codec/report_owned as codec_report_owned
import ../codec/owned as codec_owned
import ../codec/header as codec_header
import ../codec/state_safrole as codec_state_safrole
import ../codec/natural as codec_natural
import ./computed_envelope as state_computed_envelope
import ./computed_credentials as state_computed_credentials
import ./computed_guarantors as state_computed_guarantors
import ./computed_roster as state_computed_roster
import ./computed_transition as state_computed_transition
import ./computed_profile as state_computed_profile
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission
import ./store as state_store

type
  ComputedBatchError* {.pure.} = enum ## Failed/default results expose neither a prefix nor authority for an empty batch.
    Uninitialized, None, InvalidSource, LimitExceeded, ContextMismatch, NonCanonical,
    EncodingFailure, InvalidIndex
  ComputedBatchLimits* = object ## Independent source/set capacities, complete wire cap and per-header copy cap.
    guarantees*, reporters*: ElementLimit
    bytes*, headerBytes*: ByteLimit
  ComputedBatchIndex* = distinct uint64 ## Batch-relative source ordinal cannot substitute a credential index.
  ComputedBatchReporterIndex* = distinct uint64 ## Union ordinal is independent of per-guarantee reporters.
  ComputedBatchInfo* = object ## Fixed copied facts grant no context or credential replacement authority.
    guarantees*, reporters*: int
    bytes*: uint64
  ComputedBatchData = ref object ## Immutable acyclic owner retains original certificates and only fully encoded output.
    sources: seq[ComputedGuaranteeEnvelope]
    reporters: seq[StateEdKey]
    wire: seq[byte]
  ComputedGuaranteeBatch* = object ## Composition is not candidate inclusion or complete report admission.
    data: nil ComputedBatchData
  ComputedBatchResult*[T] = object ## Private complete success alone contains application data.
    case status: ComputedBatchError
    of None:
      completed: T
    else:
      discard                      # Defaults and refusals contain reasons alone.

func error*[T](outcome: ComputedBatchResult[T]): ComputedBatchError =
  ## Inspect selection without writable discriminator access.
  outcome.status
func value*[T](outcome: ComputedBatchResult[T]): T
    {.requires: outcome.status == ComputedBatchError.None.} =
  ## Preserve complete-success extraction under optimized compilation.
  outcome.completed
proc computedBatchInfo*(batch: ComputedGuaranteeBatch): ComputedBatchResult[ComputedBatchInfo] =
  ## Copy lengths without exposing retained mutable storage.
  let data = batch.data
  if data == nil: return ComputedBatchResult[ComputedBatchInfo](
      status: ComputedBatchError.Uninitialized)
  ComputedBatchResult[ComputedBatchInfo](status: ComputedBatchError.None,
    completed: ComputedBatchInfo(guarantees: data.sources.len, reporters: data.reporters.len,
      bytes: uint64(data.wire.len)))
proc computedBatchSourceAt*(batch: ComputedGuaranteeBatch,
    index: ComputedBatchIndex): ComputedBatchResult[ComputedGuaranteeEnvelope] =
  ## Share one original immutable certificate after a full-width range check.
  let data = batch.data
  if data == nil: return ComputedBatchResult[ComputedGuaranteeEnvelope](
      status: ComputedBatchError.Uninitialized)
  if uint64(index) >= uint64(data.sources.len): return ComputedBatchResult[
      ComputedGuaranteeEnvelope](status: ComputedBatchError.InvalidIndex)
  ComputedBatchResult[ComputedGuaranteeEnvelope](status: ComputedBatchError.None,
    completed: data.sources[int(uint64(index))])
proc computedBatchReporterAt*(batch: ComputedGuaranteeBatch,
    index: ComputedBatchReporterIndex): ComputedBatchResult[StateEdKey] =
  ## Copy one full lexicographically ordered unique reporter identity.
  let data = batch.data
  if data == nil: return ComputedBatchResult[StateEdKey](status: ComputedBatchError.Uninitialized)
  if uint64(index) >= uint64(data.reporters.len): return ComputedBatchResult[StateEdKey](
      status: ComputedBatchError.InvalidIndex)
  ComputedBatchResult[StateEdKey](status: ComputedBatchError.None,
    completed: data.reporters[int(uint64(index))])
proc computedBatchBytes*(batch: ComputedGuaranteeBatch): ComputedBatchResult[seq[byte]] =
  ## Copy the entire canonical guarantees extrinsic encoding into independent caller storage.
  let data = batch.data
  if data == nil: return ComputedBatchResult[seq[byte]](status: ComputedBatchError.Uninitialized)
  var copied = newSeq[byte](data.wire.len)
  for i in 0..<copied.len: copied[i] = data.wire[i] # Copy exactly the retained canonical encoding.
  ComputedBatchResult[seq[byte]](status: ComputedBatchError.None, completed: copied)
func compare(left, right: StateEdKey): int =
  ## Compare every byte of the actual identity without interpreting curve encodings.
  let a = array[32, byte](left)
  let b = array[32, byte](right)
  for i in 0..<32:
    if a[i] < b[i]: return -1 # First differing octet determines canonical set order.
    if a[i] > b[i]: return 1 # Equal prefixes do not collapse distinct identities.
  0
proc stage(source: ComputedGuaranteeEnvelope): TransitionBoundComputedReport =
  ## Caller first validates the closed envelope owner; all retained intermediate selections are complete.
  source.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value
proc prepareComputedBatch*(sources: openArray[ComputedGuaranteeEnvelope],
    limits: ComputedBatchLimits): ComputedBatchResult[ComputedGuaranteeBatch] =
  ## Preflight shared authority, canonical cores and complete budgets before allocating retained variable output.
  template fail(reason: ComputedBatchError) =
    return ComputedBatchResult[ComputedGuaranteeBatch](status: reason)
  if sources.len == 0: fail(ComputedBatchError.InvalidSource) # No original context can be derived from absence.
  if sources.len > 341 or uint64(sources.len) > uint64(limits.guarantees):
    fail(ComputedBatchError.LimitExceeded) # Bound all fixed scratch indexing before any source access.
  if sources[0].computedEnvelopeInfo.error != ComputedEnvelopeError.None:
    fail(ComputedBatchError.InvalidSource)
  let originalStage = stage(sources[0])
  let original = originalStage.computedTransitionSource.value.computedProfileContext.value
  let transition = originalStage.computedTransitionStage.value.value
  let cores = original.parameters.get(coreCount)
  if uint64(sources.len) > cores: fail(ComputedBatchError.LimitExceeded)
  let candidate = transition.admitted.admittedHeader
  let headerSize = headerInfo(candidate).value.consumed
  if uint64(headerSize) > uint64(limits.headerBytes): fail(ComputedBatchError.LimitExceeded)
  var headerWire = newSeq[byte](headerSize)
  if encodeOwnedHeader(candidate, headerWire).error != HeaderError.None:
    fail(ComputedBatchError.EncodingFailure)
  var values = default(array[341, Guarantee])
  var keys = default(array[1023, StateEdKey])
  var keyCount = 0
  var previousCore = 0'u64
  var size = uint64(encode(JamNatural(uint64(sources.len))).len)
  for ordinal, source in sources:
    # Every source must retain exactly the same complete original and authenticated posterior map versions.
    if source.computedEnvelopeInfo.error != ComputedEnvelopeError.None: fail(
        ComputedBatchError.InvalidSource)
    let selectedStage = stage(source)
    let selected = selectedStage.computedTransitionSource.value.computedProfileContext.value
    let step = selectedStage.computedTransitionStage.value.value
    if not sameStateSnapshot(original.state, selected.state) or
        not sameStateSnapshot(transition.snapshot, step.snapshot): fail(
            ComputedBatchError.ContextMismatch)
    for field in low(Parameter)..high(Parameter):
      if original.parameters.get(field) != selected.parameters.get(field):
        fail(ComputedBatchError.ContextMismatch) # All fetch-visible original parameter fields participate.
    let actual = step.admitted.admittedHeader
    let actualSize = headerInfo(actual).value.consumed
    if uint64(actualSize) > uint64(limits.headerBytes): fail(ComputedBatchError.LimitExceeded)
    if actualSize != headerSize: fail(ComputedBatchError.ContextMismatch)
    block:
      # Temporary header copies retire before whole-wire allocation; seals and every marker participate.
      var wire = newSeq[byte](actualSize)
      if encodeOwnedHeader(actual, wire).error != HeaderError.None: fail(
          ComputedBatchError.EncodingFailure)
      if wire != headerWire: fail(ComputedBatchError.ContextMismatch)
    let value = source.computedEnvelopeGuarantee.value
    let core = uint64(ownedReportInfo(value.report).value.core)
    if ordinal > 0 and core <= previousCore: fail(ComputedBatchError.NonCanonical)
    previousCore = core
    values[ordinal] = value
    let info = source.computedEnvelopeInfo.value
    if size > uint64(limits.bytes) or size > uint64(high(int)): fail(
        ComputedBatchError.LimitExceeded)
    if info.bytes > uint64(limits.bytes)-size or info.bytes > uint64(high(int))-size:
      fail(ComputedBatchError.LimitExceeded) # Subtraction proves both additions before allocation/narrowing.
    size = size+info.bytes
    for i in 0..<info.reporters:
      # Insert actual full identities into bounded scratch; repeated keys do not consume union capacity.
      let key = source.computedEnvelopeReporterAt(ComputedReporterIndex(uint64(i))).value
      var position = 0
      while position < keyCount and compare(keys[position], key) < 0:
        inc position # Find deterministic insertion point in at most 1023 fixed keys.
      let duplicate = position < keyCount and compare(keys[position], key) == 0
      if not duplicate:
        if uint64(keyCount) >= uint64(limits.reporters): fail(ComputedBatchError.LimitExceeded)
        var cursor = keyCount
        while cursor > position:
          let prior = keys[cursor-1]
          keys[cursor] = prior # Separate scalar copy avoids overlapping sequence/array aliasing.
          dec cursor
        keys[position] = key
        inc keyCount # At most three new keys per source proves capacity before each access.
  var wire = newSeq[byte](int(size))
  let config = GuaranteeConfig(cores: CoreCount(cores), validators: ValidatorCount(3*cores),
      maxBytes: ByteLimit(size))
  let encoded = encodeGuarantees(values.toOpenArray(0, sources.len-1), config, wire)
  if encoded.error != GuaranteeError.None: fail(ComputedBatchError.EncodingFailure)
  if uint64(encoded.value) != size: fail(ComputedBatchError.EncodingFailure)
  var retained = newSeq[ComputedGuaranteeEnvelope](sources.len)
  for i in 0..<sources.len: retained[i] = sources[i] # Share only validated original immutable certificates.
  var reporters = newSeq[StateEdKey](keyCount)
  for i in 0..<keyCount: reporters[i] = keys[i] # Retain exactly the complete canonical set.
  ComputedBatchResult[ComputedGuaranteeBatch](status: ComputedBatchError.None,
    completed: ComputedGuaranteeBatch(data: ComputedBatchData(sources: retained,
      reporters: reporters, wire: wire)))
