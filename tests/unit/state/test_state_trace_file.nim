# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict regular-file EOF, bounded reads and atomic exact TraceStep publication preserve existing targets on refusal.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/trace_step_context
import ../../../src/state/[trace_file, trace_step, trace_state]
import ../../../src/codec/bounded
import ../../../src/lib/atomic_file
proc text(bytes: openArray[byte]): string =
  ## Test-only exact byte materialization preserves binary zeros and all UTF-8-independent payload octets.
  result = newString(bytes.len)
  for index in 0..<bytes.len: result[index] = char(bytes[index])
proc main() {.raises.} =
  ## Every path is test-owned in the native runner's private working directory; no canonical application state is adopted here.
  let fixture = getEnv("RAGNAROK_STATE_TRACE_STEP")
  assert fixture.len != 0
  let expected = readFile(fixture)
  let limits = traceStepTestLimits()
  let missing = default(TraceFileResult)
  assert missing.error == TraceFileError.Uninitialized
  let loaded = loadTraceStepFile(fixture, limits)
  assert loaded.error == TraceFileError.None
  let owner = loaded.value
  let path = "state-trace-file-owned-input.bin"
  defer:
    var nativePath = path
    discard posix.unlink(nativePath.toCString()) # Retire only the exact test-owned regular target, including after an assertion or I/O refusal.
  let invalid = loadTraceStepFile("", limits)
  assert invalid.error == TraceFileError.FileFailure
  assert invalid.fileFailure == AtomicFileError.InvalidPath
  let absent = loadTraceStepFile(path & ".missing", limits)
  assert absent.error == TraceFileError.FileFailure and absent.fileFailure ==
      AtomicFileError.IoFailure
  let directory = loadTraceStepFile(".", limits)
  assert directory.error == TraceFileError.FileFailure and directory.fileFailure ==
      AtomicFileError.IoFailure
  var short = limits
  short.bytes = ByteLimit(expected.len-1)
  let bounded = loadTraceStepFile(fixture, short)
  assert bounded.error == TraceFileError.FileFailure and bounded.fileFailure ==
      AtomicFileError.LimitExceeded
  writeFile(path, "")
  let empty = loadTraceStepFile(path, limits)
  assert empty.error == TraceFileError.DecodeFailure
  assert empty.decodeFailure.error == TraceStepError.PreStateFailure
  assert empty.decodeFailure.stateFailure == TraceStateError.Truncated
  writeFile(path, expected & "x")
  assert loadTraceStepFile(path, limits).error == TraceFileError.TrailingBytes
  writeFile(path, expected & expected)
  assert loadTraceStepFile(path, limits).error == TraceFileError.TrailingBytes
  writeFile(path, expected.substr(0, expected.len-2))
  let truncated = loadTraceStepFile(path, limits)
  assert truncated.error == TraceFileError.DecodeFailure
  assert truncated.decodeFailure.error == TraceStepError.PostStateFailure
  var corrupt = expected
  corrupt[0] = char(byte(corrupt[0]) xor 1)
  writeFile(path, corrupt)
  let wrongRoot = loadTraceStepFile(path, limits)
  assert wrongRoot.error == TraceFileError.DecodeFailure
  assert wrongRoot.decodeFailure.stateFailure == TraceStateError.RootMismatch
  writeFile(path, "sentinel")
  let refused = saveTraceStepFile(path, owner, ByteLimit(expected.len-1))
  assert refused.error == TraceFileError.EncodeFailure and refused.encodeFailure ==
      TraceStepError.LimitExceeded
  assert readFile(path) == "sentinel"
  let noOwner = saveTraceStepFile(path, default(TraceStep), limits.bytes)
  assert noOwner.error == TraceFileError.EncodeFailure and noOwner.encodeFailure ==
      TraceStepError.InvalidOwner
  assert readFile(path) == "sentinel"
  let saved = saveTraceStepFile(path, owner, ByteLimit(expected.len))
  assert saved.error == TraceFileError.None
  assert readFile(path) == expected
  let reopened = loadTraceStepFile(path, limits)
  assert reopened.error == TraceFileError.None
  writeFile(path, "later modification")
  assert text(reopened.value.copyTraceStep(limits.bytes).value) ==
      expected # Actual EOF owners remain detached from subsequent file changes.
  let failedWrite = saveTraceStepFile(path & ".absent/child", owner, limits.bytes)
  assert failedWrite.error == TraceFileError.FileFailure and failedWrite.fileFailure ==
      AtomicFileError.IoFailure
  echo "PASS published TraceStep files: bounded EOF, exact bytes and refusal-safe atomic output"
try:
  main() # Test fixture and filesystem failures must fail the complete native suite.
except:
  quit(2)
