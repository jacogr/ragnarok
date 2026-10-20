# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded startup-only full-checkpoint reads close every file before returning owned state.
## Filesystem operations are synchronous and never belong in networking callbacks.

import ../lib/atomic_file
import ./[checkpoint, store]
import ../codec/[bounded, state_trie]

type
  CheckpointFileError* {.pure.} = enum ## I/O and format refusals cannot publish partial restored state.
    Uninitialized, None, InvalidPath, IoFailure, LimitExceeded, InvalidCheckpoint,
      PublishedUnsynced, Busy
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

func fileError(reason: AtomicFileError): CheckpointFileError =
  ## Preserve raw I/O lifecycle outcomes without granting a checkpoint payload or format authority.
  case reason
  of AtomicFileError.Uninitialized: CheckpointFileError.Uninitialized # Defaults remain uninitialized.
  of AtomicFileError.None: CheckpointFileError.None # Only actual completed I/O is successful.
  of AtomicFileError.InvalidPath: CheckpointFileError.InvalidPath # Preserve destination identity refusal.
  of AtomicFileError.IoFailure: CheckpointFileError.IoFailure # Preserve actual filesystem failures.
  of AtomicFileError.LimitExceeded: CheckpointFileError.LimitExceeded # No refused prefix becomes a payload.
  of AtomicFileError.PublishedUnsynced: CheckpointFileError.PublishedUnsynced # Visibility never implies confirmed durability.

proc loadFullCheckpoint*(path: string, limits: StateStoreLimits,
    limit: ByteLimit): CheckpointFileResult[StateStore] =
  ## Return state only after bounded EOF, strict canonical decoding and complete-root verification.
  let read = readBoundedFile(path, limit)
  if read.error != AtomicFileError.None:
    return CheckpointFileResult[StateStore](status: fileError(
        read.error)) # All raw-reader failures are payload-free path/I/O/size alternatives.
  let decoded = decodeFullCheckpoint(read.value, limits, limit)
  if decoded.error != CheckpointError.None:
    return CheckpointFileResult[StateStore](status: CheckpointFileError.InvalidCheckpoint,
      reason: decoded.error)
  CheckpointFileResult[StateStore](status: CheckpointFileError.None, completed: decoded.value)

proc saveFullCheckpoint*(path: string, snapshot: StateStoreSnapshot,
    limit: ByteLimit): CheckpointFileResult[StateStoreSnapshot] =
  ## Encode before I/O; sync/close a unique sibling, rename, then sync the stable parent directory.
  ## Caller serializes writers and keeps the directory namespace/working directory stable for this call.
  if path.len == 0 or path.len > high(int) - 16:
    return CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.InvalidPath)
  for character in path:
    if character == char(0):
      return CheckpointFileResult[StateStoreSnapshot](
          status: CheckpointFileError.InvalidPath) # No C path truncation may change the destination identity.
  let encoded = encodeFullCheckpoint(snapshot, limit)
  if encoded.error != CheckpointError.None:
    return CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.InvalidCheckpoint,
      reason: encoded.error) # A refusal occurs before temporary-file or directory ownership starts.
  let published = replaceAtomicFile(path, encoded.value, limit)
  if published != AtomicFileError.None:
    return CheckpointFileResult[StateStoreSnapshot](status: fileError(
        published)) # Every raw refusal preserves its exact lifecycle meaning.
  CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.None, completed: snapshot)

proc loadFullCheckpoint*(path: string, expected: StateRoot, limits: StateStoreLimits,
    limit: ByteLimit): CheckpointFileResult[StateStore] =
  ## Anchor bounded file restoration to a complete-state commitment supplied independently of the file.
  let loaded = loadFullCheckpoint(path, limits, limit)
  if loaded.error != CheckpointFileError.None:
    return loaded # A trust check must not replace a genuine file/decoder refusal with success.
  let actual = array[32, byte](loaded.value.snapshot.value.commitment.root)
  let wanted = array[32, byte](expected)
  for index in 0..<32:
    if actual[index] != wanted[index]:
      return CheckpointFileResult[StateStore](status: CheckpointFileError.InvalidCheckpoint,
        reason: CheckpointError.RootMismatch) # Drop the complete but unauthorized candidate before any caller can adopt it.
  loaded
