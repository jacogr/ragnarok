# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded offline TraceStep files require exact EOF and preserve atomic publication outcomes.
## Files carry framed comparison inputs only; actual-chain STF import remains a separate application operation.
import ./trace_step as state_trace_step
import ../codec/bounded as codec_bounded
import ../lib/atomic_file as lib_atomic_file

type
  TraceFileError* {.pure.} = enum ## File, codec and exact-extent refusals expose no owned trace prefix or successful receipt.
    Uninitialized, None, FileFailure, DecodeFailure, TrailingBytes, EncodeFailure
  TraceFileResult* = object ## Only complete EOF decoding or completed durable publication exposes the original immutable trace owner.
    case status: TraceFileError
    of None: completed: TraceStep
    of FileFailure: fileReason: AtomicFileError
    of DecodeFailure: decodeReason: TraceStepResult[TraceStep]
    of EncodeFailure: encodeReason: TraceStepError
    else: discard # Defaults and trailing bytes contain no successful owner or field extent.

func error*(outcome: TraceFileResult): TraceFileError =
  ## Observe only the selected immutable completion stage.
  outcome.status
func value*(outcome: TraceFileResult): TraceStep {.inline,
    requires: outcome.status == TraceFileError.None.} =
  ## Extract only a complete exact-file owner or completed publication's original owner.
  outcome.completed
func fileFailure*(outcome: TraceFileResult): AtomicFileError {.inline,
    requires: outcome.status == TraceFileError.FileFailure.} =
  ## Preserve native path/read/close/publication outcomes, including visible-but-unsynced failure.
  outcome.fileReason
func decodeFailure*(outcome: TraceFileResult): TraceStepResult[TraceStep] {.inline,
    requires: outcome.status == TraceFileError.DecodeFailure.} =
  ## Retain the actual failed field/root reason without exposing a usable prefix.
  outcome.decodeReason
func encodeFailure*(outcome: TraceFileResult): TraceStepError {.inline,
    requires: outcome.status == TraceFileError.EncodeFailure.} =
  ## Preserve default-owner and output-ceiling refusal before opening a publication target.
  outcome.encodeReason

proc loadTraceStepFile*(path: string, limits: TraceStepLimits): TraceFileResult =
  ## Read only bounded regular-file EOF through the existing descriptor-safe helper, then reject every trailing octet before exposing an owner.
  let loaded = readBoundedFile(path, limits.bytes)
  if loaded.error != AtomicFileError.None:
    return TraceFileResult(status: TraceFileError.FileFailure, fileReason: loaded.error)
  let bytes = loaded.value
  let decoded = decodeTraceStep(bytes, limits)
  if decoded.error != TraceStepError.None:
    return TraceFileResult(status: TraceFileError.DecodeFailure, decodeReason: decoded)
  if decoded.value.traceStepBytes.value != bytes.len:
    return TraceFileResult(status: TraceFileError.TrailingBytes) # A valid prefix or concatenated step is not a complete single TraceStep file.
  TraceFileResult(status: TraceFileError.None, completed: decoded.value)

proc saveTraceStepFile*(path: string, step: TraceStep, bytes: ByteLimit): TraceFileResult =
  ## Preflight/copy the immutable complete wire before atomic replacement; callers own offline scheduling and a stable directory namespace.
  let encoded = step.copyTraceStep(bytes)
  if encoded.error != TraceStepError.None:
    return TraceFileResult(status: TraceFileError.EncodeFailure, encodeReason: encoded.error)
  let published = replaceAtomicFile(path, encoded.value, bytes)
  if published != AtomicFileError.None:
    return TraceFileResult(status: TraceFileError.FileFailure,
        fileReason: published) # A visible-but-unsynced replacement remains a typed failure, never an invented durable receipt.
  TraceFileResult(status: TraceFileError.None, completed: step)
