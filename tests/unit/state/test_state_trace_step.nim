# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete published TraceStep ownership, exact child boundaries and typed failure isolation.
import std/[assertions, envvars, syncio]
import ../../support/trace_step_context
import ../../../src/state/trace/[step as trace_step, state as trace_state]
import ../../../src/state/store
import ../../../src/codec/[block_codec, bounded, header, assurances]
proc main() {.raises.} =
  ## Independent frozen wire is an input only; expected complete maps live in the mathematical corpus.
  let path = getEnv("RAGNAROK_STATE_TRACE_STEP")
  assert path.len != 0
  let text = readFile(path)
  var expected = newSeq[byte](text.len)
  for index in 0..<text.len: expected[index] = byte(text[
      index]) # Preserve exact binary fixture bytes before any destructive ownership probe.
  let limits = traceStepTestLimits()
  let absent = default(TraceStep)
  let missing = default(TraceStepResult[TraceStep])
  assert missing.error == TraceStepError.Uninitialized
  assert absent.traceStepBytes.error == TraceStepError.InvalidOwner
  assert absent.tracePreState.error == TraceStepError.InvalidOwner
  assert absent.traceBlock.error == TraceStepError.InvalidOwner
  assert absent.tracePostState.error == TraceStepError.InvalidOwner
  assert absent.copyTraceStep(limits.bytes).error == TraceStepError.InvalidOwner
  var input = expected
  input.add(255)
  var outcome = decodeTraceStep(input, limits)
  assert outcome.error == TraceStepError.None
  var owner = outcome.value
  let before = owner.tracePreState.value
  let body = owner.traceBlock.value
  let after = owner.tracePostState.value
  let first = before.traceStateInfo.value.consumed
  let middle = body.blockInfo.value.consumed
  assert owner.traceStepBytes.value == expected.len
  for index in 0..<input.len: input[index] = 0 # Captured children own their bytes, not the caller's mutable input.
  var copied = owner.copyTraceStep(limits.bytes).value
  assert copied == expected
  copied[0] = copied[0] xor 1
  assert owner.copyTraceStep(limits.bytes).value == expected
  for ceiling in 0..<expected.len:
    assert owner.copyTraceStep(ByteLimit(ceiling)).error ==
        TraceStepError.LimitExceeded # Refuse every short total output before copying any child.
  assert newTraceStep(before, body, after, ByteLimit(expected.len-1)).error ==
      TraceStepError.LimitExceeded
  assert newTraceStep(before, body, default(TraceState), limits.bytes).error ==
      TraceStepError.InvalidOwner
  outcome = default(TraceStepResult[TraceStep])
  owner = default(TraceStep)
  let recaptured = newTraceStep(before, body, after, limits.bytes)
  assert recaptured.error == TraceStepError.None
  assert recaptured.value.copyTraceStep(limits.bytes).value ==
      expected # Detached child handles survive release of both enclosing result and owner.
  var bad = expected
  bad[0] = bad[0] xor 1
  let badPre = decodeTraceStep(bad, limits)
  assert badPre.error == TraceStepError.PreStateFailure and badPre.stateFailure ==
      TraceStateError.RootMismatch
  bad = expected
  bad[first+middle] = bad[first+middle] xor 1
  let badPost = decodeTraceStep(bad, limits)
  assert badPost.error == TraceStepError.PostStateFailure and badPost.stateFailure ==
      TraceStateError.RootMismatch
  var invalid = limits
  invalid.frame.cores = CoreCount(0)
  let badBlock = decodeTraceStep(expected, invalid)
  assert badBlock.error == TraceStepError.BlockFailure
  assert badBlock.blockFailure.error == FrameError.InvalidConfig
  for extent in [1, 31, first-1, first+1, first+middle+1, expected.len-1]:
    var short = newSeq[byte](extent)
    for index in 0..<extent: short[index] = expected[
        index] # Cut all three schema fields without replaying already-covered RawState byte boundaries.
    assert decodeTraceStep(short, limits).error != TraceStepError.None
  echo "PASS published TraceStep: exact fields, immutable children and typed atomic failures"
try:
  main() # Missing fixtures or I/O errors must fail the complete native suite.
except:
  quit(2)
