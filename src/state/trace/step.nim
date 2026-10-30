# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published TraceStep composition owns one pre-state, full block and post-state in normative order.
## Wire capture validates framing and complete opaque roots, not STF execution, signatures or chain authority.
import std/assertions
import ./state as trace_state
import ../store
import ../../codec/[block_codec, bounded]

type
  TraceStepError* {.pure.} = enum ## Each failed field retains its genuine typed failure without a successful prefix.
    Uninitialized, None, InvalidOwner, LimitExceeded, PreStateFailure, BlockFailure, PostStateFailure
  TraceStepResult*[T] = object ## Private alternatives prevent failed/default parsing from exposing progress or child owners.
    case status: TraceStepError
    of None: completed: T
    of PreStateFailure, PostStateFailure: stateReason: TraceStateError
    of BlockFailure: frameReason: FrameResult[BlockRead]
    else: discard # Plain failures contain no field progress or fabricated child.
  TraceStepData = ref object ## Immutable acyclic composition retains each original child and its exact total prefix extent.
    before, after: TraceState
    body: OwnedBlock
    consumed: int
  TraceStep* = object ## Child getters retain their immutable owner even after this enclosing step is released.
    data: nil TraceStepData
  TraceStepLimits* = object ## Chain structural domains and both state/resource policies are explicit caller inputs, absent from the wire schema.
    frame*: FrameConfig
    state*: StateStoreLimits
    bytes*: ByteLimit

func error*[T](outcome: TraceStepResult[T]): TraceStepError =
  ## Observe the selected immutable stage without authorizing extraction.
  outcome.status

func value*[T](outcome: TraceStepResult[T]): T {.inline,
    requires: outcome.status == TraceStepError.None.} =
  ## Extract only complete successful owners, copied bytes or scalar observations.
  outcome.completed

func stateFailure*[T](outcome: TraceStepResult[T]): TraceStateError {.inline,
    requires: outcome.status in {TraceStepError.PreStateFailure,
        TraceStepError.PostStateFailure}.} =
  ## Preserve the actual failing RawState reason without exposing either child.
  outcome.stateReason

func blockFailure*[T](outcome: TraceStepResult[T]): FrameResult[BlockRead] {.inline,
    requires: outcome.status == TraceStepError.BlockFailure.} =
  ## Preserve the original failed block frame and its guarded nested component reason.
  outcome.frameReason

func fail[T](reason: TraceStepError): TraceStepResult[T] =
  ## Plain resource/default refusals cannot carry a completed composition.
  TraceStepResult[T](status: reason)

proc newTraceStep*(before: TraceState, body: OwnedBlock, after: TraceState,
    bytes: ByteLimit): TraceStepResult[TraceStep] =
  ## Retain three already validated immutable children after proving their entire combined extent; infer no execution relation.
  let first = before.traceStateInfo
  let middle = body.blockInfo
  let last = after.traceStateInfo
  if first.error != TraceStateError.None or middle.error != FrameError.None or last.error !=
      TraceStateError.None:
    return fail[TraceStep](TraceStepError.InvalidOwner)
  let maximum = min(uint64(bytes), uint64(high(int)))
  var extent = 0'u64
  for size in [first.value.consumed, middle.value.consumed, last.value.consumed]:
    if uint64(size) > maximum-extent: return fail[TraceStep](TraceStepError.LimitExceeded)
    extent += uint64(size) # Complete child extents are positive and every addition fits the native output domain.
  TraceStepResult[TraceStep](status: TraceStepError.None, completed: TraceStep(
      data: TraceStepData(before: before, body: body, after: after, consumed: int(extent))))

proc decodeTraceStep*(input: openArray[byte], limits: TraceStepLimits): TraceStepResult[TraceStep] =
  ## Borrow stable input synchronously and retain only one fully validated prefix; later fields cannot leak into child ownership.
  let maximum = int(min(uint64(input.len), uint64(limits.bytes)))
  let before = decodeTraceState(input, limits.state, limits.bytes)
  if before.error != TraceStateError.None:
    return TraceStepResult[TraceStep](status: TraceStepError.PreStateFailure,
        stateReason: before.error)
  var offset = before.value.traceStateInfo.value.consumed
  var frame = limits.frame
  frame.maxBytes = ByteLimit(min(uint64(frame.maxBytes), uint64(maximum-offset)))
  let body = if offset < maximum: decodeBlock(input.toOpenArray(offset, maximum-1), frame)
      else: decodeBlock([], frame) # An absent middle field retains the existing typed block refusal.
  if body.error != FrameError.None:
    return TraceStepResult[TraceStep](status: TraceStepError.BlockFailure, frameReason: body)
  offset += body.value.consumed
  let after = if offset < input.len: decodeTraceState(input.toOpenArray(offset, input.high),
      limits.state, ByteLimit(maximum-offset))
      else: decodeTraceState([], limits.state, ByteLimit(
          0)) # A missing final field remains an actual RawState truncation.
  if after.error != TraceStateError.None:
    return TraceStepResult[TraceStep](status: TraceStepError.PostStateFailure,
        stateReason: after.error)
  newTraceStep(before.value, body.value.owner, after.value, limits.bytes)

proc traceStepBytes*(step: TraceStep): TraceStepResult[int] =
  ## Successful prefix extent belongs to the same immutable three-field owner.
  let data = step.data
  if data == nil: return fail[int](TraceStepError.InvalidOwner)
  TraceStepResult[int](status: TraceStepError.None, completed: data.consumed)

proc tracePreState*(step: TraceStep): TraceStepResult[TraceState] =
  ## Retain the original exact pre-state owner, including its record order and recomputed opaque map.
  let data = step.data
  if data == nil: return fail[TraceState](TraceStepError.InvalidOwner)
  TraceStepResult[TraceState](status: TraceStepError.None, completed: data.before)

proc traceBlock*(step: TraceStep): TraceStepResult[OwnedBlock] =
  ## Retain the complete schema-qualified block and the structural configuration under which it was captured.
  let data = step.data
  if data == nil: return fail[OwnedBlock](TraceStepError.InvalidOwner)
  TraceStepResult[OwnedBlock](status: TraceStepError.None, completed: data.body)

proc tracePostState*(step: TraceStep): TraceStepResult[TraceState] =
  ## Retain the original complete post-state without claiming that the block produced it.
  let data = step.data
  if data == nil: return fail[TraceState](TraceStepError.InvalidOwner)
  TraceStepResult[TraceState](status: TraceStepError.None, completed: data.after)

proc copyTraceStep*(step: TraceStep, bytes: ByteLimit): TraceStepResult[seq[byte]] =
  ## Preflight total output before copying any child; detached bytes preserve the exact captured field order.
  let data = step.data
  if data == nil: return fail[seq[byte]](TraceStepError.InvalidOwner)
  if uint64(data.consumed) > uint64(bytes): return fail[seq[byte]](TraceStepError.LimitExceeded)
  var output = newSeq[byte](data.consumed)
  let first = data.before.copyTraceState(bytes).value
  let last = data.after.copyTraceState(bytes).value
  var offset = 0
  for octet in first:
    output[offset] = octet
    inc offset # Original validated child extents prove every destination coordinate.
  let middle = data.body.blockInfo.value.consumed
  let encoded = data.body.encodeOwnedBlock(output.toOpenArray(offset, offset+middle-1))
  assert encoded.error == FrameError.None and encoded.value == middle
  offset += middle
  for octet in last:
    output[offset] = octet
    inc offset # The final field exactly fills the already admitted total output.
  assert offset == output.len
  TraceStepResult[seq[byte]](status: TraceStepError.None, completed: output)
