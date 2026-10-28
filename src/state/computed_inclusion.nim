# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Require exact computed batch bytes in its own authenticated candidate guarantee component.

import ../codec/bounded as codec_bounded
import ../codec/block_codec as codec_block_codec
import ./computed_batch as state_computed_batch
import ./computed_envelope as state_computed_envelope
import ./computed_credentials as state_computed_credentials
import ./computed_guarantors as state_computed_guarantors
import ./computed_roster as state_computed_roster
import ./computed_transition as state_computed_transition
import ./block_transition as state_block_transition
import ./block_admission as state_block_admission

type
  ComputedInclusionError* {.pure.} = enum ## Refusals carry no partially included batch or detached candidate.
    Uninitialized, None, InvalidSource, LimitExceeded, GuaranteeMismatch, EncodingFailure
  ComputedInclusionData = ref object ## Immutable acyclic owner retains only the original batch and its genuine stage.
    source: ComputedGuaranteeBatch
    staged: BlockTransitionResult
    component: GuaranteeComponent
  IncludedComputedGuarantees* = object ## Exact inclusion does not certify complete report policy or publish a block.
    data: nil ComputedInclusionData
  ComputedInclusionResult*[T] = object ## Private complete success is the only alternative with application data.
    case status: ComputedInclusionError
    of None:
      completed: T
    else:
      discard # Defaults/refusals expose their selected reasons alone.

func error*[T](outcome: ComputedInclusionResult[T]): ComputedInclusionError =
  ## Inspect status without permitting discriminator mutation.
  outcome.status
func value*[T](outcome: ComputedInclusionResult[T]): T
    {.requires: outcome.status == ComputedInclusionError.None.} =
  ## Preserve complete-success extraction under optimized compilation.
  outcome.completed
proc computedInclusionSource*(included: IncludedComputedGuarantees): ComputedInclusionResult[
    ComputedGuaranteeBatch] =
  ## Share all original computed certificates and the canonical reporter union.
  let data = included.data
  if data == nil: return ComputedInclusionResult[ComputedGuaranteeBatch](
      status: ComputedInclusionError.Uninitialized)
  ComputedInclusionResult[ComputedGuaranteeBatch](status: ComputedInclusionError.None,
      completed: data.source)
proc computedInclusionStage*(included: IncludedComputedGuarantees): ComputedInclusionResult[
    BlockTransitionResult] =
  ## Share the exact private successful candidate prefix, with no caller replacement tuple.
  let data = included.data
  if data == nil: return ComputedInclusionResult[BlockTransitionResult](
      status: ComputedInclusionError.Uninitialized)
  ComputedInclusionResult[BlockTransitionResult](status: ComputedInclusionError.None,
      completed: data.staged)
proc computedInclusionComponent*(included: IncludedComputedGuarantees): ComputedInclusionResult[
    GuaranteeComponent] =
  ## Retain the original candidate's immutable guarantees, independently of caller handles.
  let data = included.data
  if data == nil: return ComputedInclusionResult[GuaranteeComponent](
      status: ComputedInclusionError.Uninitialized)
  ComputedInclusionResult[GuaranteeComponent](status: ComputedInclusionError.None,
      completed: data.component)
proc bindComputedInclusion*(source: ComputedGuaranteeBatch,
    bytes: ByteLimit): ComputedInclusionResult[IncludedComputedGuarantees] =
  ## Derive candidate authority solely from completed batch sources and compare complete canonical guarantee encodings.
  template fail(reason: ComputedInclusionError) =
    return ComputedInclusionResult[IncludedComputedGuarantees](status: reason)
  let facts = source.computedBatchInfo
  if facts.error != ComputedBatchError.None: fail(ComputedInclusionError.InvalidSource)
  let first = source.computedBatchSourceAt(ComputedBatchIndex(0)).value
  let bound = first.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value
  let staged = bound.computedTransitionStage.value
  let candidate = staged.value.admitted.admittedBlock
  let component = candidate.blockExtrinsic.value.extrinsicGuarantees.value
  let actual = component.componentInfo.value
  if actual.records != facts.value.guarantees: fail(ComputedInclusionError.GuaranteeMismatch)
  if uint64(actual.consumed) > uint64(bytes) or facts.value.bytes > uint64(bytes):
    fail(ComputedInclusionError.LimitExceeded) # Independent whole copies are bounded before either allocation.
  if uint64(actual.consumed) != facts.value.bytes: fail(ComputedInclusionError.GuaranteeMismatch)
  var wire = newSeq[byte](actual.consumed)
  if encodeComponent(component, wire).error != FrameError.None: fail(
      ComputedInclusionError.EncodingFailure)
  if wire != source.computedBatchBytes.value: fail(ComputedInclusionError.GuaranteeMismatch)
  ComputedInclusionResult[IncludedComputedGuarantees](status: ComputedInclusionError.None,
    completed: IncludedComputedGuarantees(data: ComputedInclusionData(source: source,
      staged: staged, component: component)))
