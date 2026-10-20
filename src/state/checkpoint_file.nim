# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded startup-only full-checkpoint reads close every file before returning owned state.
## Filesystem operations are synchronous and never belong in networking callbacks.

import std/syncio
import ./[checkpoint, store]
import ../codec/bounded

type
  CheckpointFileError* {.pure.} = enum ## I/O and format refusals cannot publish partial restored state.
    Uninitialized, None, InvalidPath, IoFailure, LimitExceeded, InvalidCheckpoint
  CheckpointFileResult*[T] = object ## Only successful alternatives retain a completed owned payload.
    case status: CheckpointFileError
    of None:
      completed: T
    of InvalidCheckpoint:
      reason: CheckpointError
    else:
      discard                       # File/path failures contain no decoded state or successful byte prefix.

func error*[T](outcome: CheckpointFileResult[T]): CheckpointFileError =
  ## Inspect the outer boundary without extracting state or an unrelated format reason.
  outcome.status
func value*[T](outcome: CheckpointFileResult[T]): T {.inline,
    requires: outcome.status == CheckpointFileError.None.} =
  ## A restored payload is available only after file completion and full decoder success.
  outcome.completed
func checkpointError*[T](outcome: CheckpointFileResult[T]): CheckpointError {.requires:
    outcome.status == CheckpointFileError.InvalidCheckpoint.} =
  ## Preserve an actual inner decoder refusal; other alternatives have no such diagnostic.
  outcome.reason

proc readBounded(path: string, limit: ByteLimit): CheckpointFileResult[seq[byte]] =
  ## Read at most the ceiling plus one detection byte, without trusting file size or allocating it upfront.
  if path.len == 0:
    return CheckpointFileResult[seq[byte]](status: CheckpointFileError.InvalidPath)
  for character in path:
    if character == char(0):
      return CheckpointFileResult[seq[byte]](status: CheckpointFileError.InvalidPath) # C paths must not silently truncate the caller's identity.
  var file: File = nil
  if not open(file, path, fmRead):
    return CheckpointFileResult[seq[byte]](status: CheckpointFileError.IoFailure)
  defer: close(file) # Every success, decode refusal, read failure and size refusal retires this exact descriptor.
  let maximum = min(uint64(limit), uint64(high(int)))
  var bytes: seq[byte] = @[]
  var buffer = default(array[4096, byte])
  while true:
    let remaining = maximum - uint64(bytes.len)
    let requested = int(min(remaining, 4095'u64)) + 1
    let count = readBuffer(file, addr buffer[0], requested)
    if count < 0 or file.failed:
      return CheckpointFileResult[seq[byte]](status: CheckpointFileError.IoFailure) # EOF is accepted only without the native error flag.
    if count == 0: break # Only actual EOF authorizes complete decoding.
    if uint64(count) > remaining:
      return CheckpointFileResult[seq[byte]](status: CheckpointFileError.LimitExceeded) # Detect concurrent growth without retaining a byte beyond the ceiling.
    for index in 0..<count:
      bytes.add(buffer[index]) # remaining and the fixed request cap prove host extent and buffer indexing.
  CheckpointFileResult[seq[byte]](status: CheckpointFileError.None, completed: bytes)

proc loadFullCheckpoint*(path: string, limits: StateStoreLimits,
    limit: ByteLimit): CheckpointFileResult[StateStore] =
  ## Return state only after bounded EOF, strict canonical decoding and complete-root verification.
  let read = readBounded(path, limit)
  if read.error != CheckpointFileError.None:
    return CheckpointFileResult[StateStore](status: read.error) # All raw-reader failures are payload-free path/I/O/size alternatives.
  let decoded = decodeFullCheckpoint(read.value, limits, limit)
  if decoded.error != CheckpointError.None:
    return CheckpointFileResult[StateStore](status: CheckpointFileError.InvalidCheckpoint,
      reason: decoded.error)
  CheckpointFileResult[StateStore](status: CheckpointFileError.None, completed: decoded.value)
