# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded startup-only full-checkpoint reads close every file before returning owned state.
## Filesystem operations are synchronous and never belong in networking callbacks.

import std/syncio
import std/posix/posix
import ./[checkpoint, store]
import ../codec/[bounded, state_trie]

type
  CheckpointFileError* {.pure.} = enum ## I/O and format refusals cannot publish partial restored state.
    Uninitialized, None, InvalidPath, IoFailure, LimitExceeded, InvalidCheckpoint, PublishedUnsynced
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

proc temporaryFile(path: cstring): cint {.importc: "mkstemp", cdecl, header: "<stdlib.h>".}
  ## Standard libc atomically creates a unique private 0600 file and fills the six-byte suffix.
proc synchronize(fd: cint): cint {.importc: "fsync", cdecl, header: "<unistd.h>".}
  ## File and directory durability use the actual OS syscall, with explicit failure propagation.
proc replaceFile(source, destination: cstring): cint {.importc: "rename", cdecl,
    header: "<stdio.h>".}
  ## Same-directory replacement publishes one entire synced checkpoint atomically.

proc parent(path: string): string =
  ## Retain the destination directory separately for its post-rename synchronization.
  var slash = -1
  for index, character in path:
    if character == '/': slash = index # The last separator identifies the exact parent path.
  if slash < 0: return "." # A bare filename belongs to the stable caller working directory.
  if slash == 0: return "/" # Root-level filenames retain the root directory itself.
  result = ""
  for index in 0..<slash:
    result.add(path[index]) # The discovered separator proves each copied parent coordinate.

proc saveFullCheckpoint*(path: string, snapshot: StateStoreSnapshot,
    limit: ByteLimit): CheckpointFileResult[StateStoreSnapshot] =
  ## Encode before I/O; sync/close a unique sibling, rename, then sync the stable parent directory.
  ## Caller serializes writers and keeps the directory namespace/working directory stable for this call.
  if path.len == 0:
    return CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.InvalidPath)
  for character in path:
    if character == char(0):
      return CheckpointFileResult[StateStoreSnapshot](
          status: CheckpointFileError.InvalidPath) # No C path truncation may change the destination identity.
  let encoded = encodeFullCheckpoint(snapshot, limit)
  if encoded.error != CheckpointError.None:
    return CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.InvalidCheckpoint,
      reason: encoded.error) # A refusal occurs before temporary-file or directory ownership starts.
  var directoryPath = parent(path)
  let directory = posix.open(directoryPath.toCString(), O_RDONLY)
  if directory < 0:
    return CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.IoFailure)
  defer: discard posix.close(directory) # The exact parent descriptor remains alive until after rename synchronization.
  var temporaryPath = path & ".tmp.XXXXXX"
  let temporaryName = temporaryPath.toCString()
  var descriptor = temporaryFile(temporaryName)
  if descriptor < 0:
    return CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.IoFailure)
  var renamed = false
  defer:
    if descriptor >= 0: discard posix.close(descriptor) # A failed write/sync still retires its descriptor once.
    if not renamed: discard posix.unlink(temporaryName) # Attempt to remove only this operation's own unique temporary on pre-publication failure.
  let bytes = encoded.value
  var offset = 0
  while offset < bytes.len:
    let count = posix.write(descriptor, cast[pointer](unsafeAddr bytes[offset]), bytes.len - offset)
    if count <= 0 or count > bytes.len - offset:
      return CheckpointFileResult[StateStoreSnapshot](
          status: CheckpointFileError.IoFailure) # Zero/failed writes cannot spin or advance a fabricated offset.
    offset += count
  if synchronize(descriptor) != 0:
    return CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.IoFailure)
  let closing = descriptor
  descriptor = -1 # Never retry an interrupted close against a potentially reused descriptor number.
  if posix.close(closing) != 0:
    return CheckpointFileResult[StateStoreSnapshot](status: CheckpointFileError.IoFailure)
  var destination = path
  if replaceFile(temporaryName, destination.toCString()) != 0:
    return CheckpointFileResult[StateStoreSnapshot](
        status: CheckpointFileError.IoFailure) # The prior destination remains published on ordinary rename refusal.
  renamed = true
  if synchronize(directory) != 0:
    return CheckpointFileResult[StateStoreSnapshot](
        status: CheckpointFileError.PublishedUnsynced) # New complete bytes are visible, but durability must not be claimed.
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
