# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded whole-file reads and atomic byte publication preserve exact bytes and explicit durability outcomes.
## Callers serialize writers, keep the directory namespace stable and retain immutable input through the call.

import std/posix/posix
import ../../codec/bounded

type AtomicFileError* {.pure.} = enum ## Success is explicit; visible-but-unsynced publication never becomes None.
  Uninitialized, None, InvalidPath, IoFailure, LimitExceeded, PublishedUnsynced, Busy

type BoundedFileResult* = object ## Only actual bounded EOF exposes owned bytes; default/refused alternatives have no prefix.
  case status: AtomicFileError
  of None:
    completed: seq[byte]
  else:
    discard # File read failures contain no partial buffer or open descriptor.

func error*(outcome: BoundedFileResult): AtomicFileError =
  ## Observe only completion/refusal, without exposing unvalidated bytes.
  outcome.status
func value*(outcome: BoundedFileResult): seq[byte] {.inline,
    requires: outcome.status == AtomicFileError.None.} =
  ## Caller-owned bytes are extractable only after complete EOF and descriptor retirement.
  outcome.completed

proc openDescriptor(path: cstring, flags: cint): cint {.importc: "open", cdecl,
    header: "<fcntl.h>".}
  ## The SDK supplies open's actual variadic ABI; non-creation opens use its two mandatory arguments.

proc readBoundedFile*(path: string, limit: ByteLimit): BoundedFileResult =
  ## Open nonblocking, require a regular persistence file and read at most the ceiling plus one detection byte.
  if path.len == 0 or path.len > high(int) - 16:
    return BoundedFileResult(status: AtomicFileError.InvalidPath)
  for character in path:
    if character == char(0):
      return BoundedFileResult(status: AtomicFileError.InvalidPath) # No C path truncation may change the selected identity.
  var nativePath = path
  var descriptor = openDescriptor(nativePath.toCString(), O_RDONLY or O_CLOEXEC or O_NONBLOCK)
  if descriptor < 0:
    return BoundedFileResult(status: AtomicFileError.IoFailure)
  defer:
    if descriptor >= 0: discard posix.close(descriptor) # Every read/kind/ceiling refusal still retires this exact descriptor.
  var metadata = default(Stat)
  if posix.fstat(descriptor, metadata) != 0 or not S_ISREG(metadata.st_mode):
    return BoundedFileResult(status: AtomicFileError.IoFailure) # Directory/FIFO/device input cannot become an empty successful record.
  let maximum = min(uint64(limit), uint64(high(int)))
  var bytes: seq[byte] = @[]
  var buffer = default(array[4096, byte])
  while true:
    let remaining = maximum - uint64(bytes.len)
    let requested = int(min(remaining, 4095'u64)) + 1
    let count = posix.read(descriptor, addr buffer[0], requested)
    if count < 0:
      return BoundedFileResult(status: AtomicFileError.IoFailure) # A native error cannot be interpreted as EOF or a successful prefix.
    if count == 0: break # Only actual regular-file EOF authorizes complete bytes.
    if uint64(count) > remaining:
      return BoundedFileResult(status: AtomicFileError.LimitExceeded) # Detect growth without retaining an octet beyond the ceiling.
    for index in 0..<count:
      bytes.add(buffer[index]) # The fixed request and remaining capacity prove indexing and host extent.
  let closing = descriptor
  descriptor = -1 # Never retry a possibly reused descriptor after an interrupted close.
  if posix.close(closing) != 0:
    return BoundedFileResult(status: AtomicFileError.IoFailure) # A reported retirement failure must not authorize returned bytes.
  BoundedFileResult(status: AtomicFileError.None, completed: bytes)

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

proc publishAtomicFile(path: string, bytes: openArray[byte],
    limit: ByteLimit, replace: bool): AtomicFileError =
  ## Preflight path and complete payload before creating a sibling; perform file-sync/rename/directory-sync.
  if path.len == 0 or path.len > high(int) - 16:
    return AtomicFileError.InvalidPath # Prove suffix arithmetic before any owned path construction.
  for character in path:
    if character == char(0): return AtomicFileError.InvalidPath # A C path must preserve the caller's exact destination identity.
  if uint64(bytes.len) > uint64(limit): return AtomicFileError.LimitExceeded # No filesystem resource exists before complete payload admission.
  var directoryPath = parent(path)
  let directory = openDescriptor(directoryPath.toCString(), O_RDONLY)
  if directory < 0:
    return AtomicFileError.IoFailure # The previous target remains untouched when its parent cannot open.
  defer: discard posix.close(directory) # The exact parent descriptor remains alive until after rename synchronization.
  var temporaryPath = path & ".tmp.XXXXXX"
  let temporaryName = temporaryPath.toCString()
  var descriptor = temporaryFile(temporaryName)
  if descriptor < 0:
    return AtomicFileError.IoFailure # Unique sibling creation must complete before any write.
  var renamed = false
  defer:
    if descriptor >= 0: discard posix.close(descriptor) # A failed write/sync still retires its descriptor once.
    if not renamed: discard posix.unlink(temporaryName) # Attempt to remove only this operation's own unique temporary on pre-publication failure.
  var offset = 0
  while offset < bytes.len:
    let count = posix.write(descriptor, cast[pointer](unsafeAddr bytes[offset]), bytes.len - offset)
    if count <= 0 or count > bytes.len - offset:
      return AtomicFileError.IoFailure # Zero/failed writes cannot spin or advance a fabricated offset.
    offset += count
  if synchronize(descriptor) != 0:
    return AtomicFileError.IoFailure # Unsynchronized content cannot replace the old destination.
  let closing = descriptor
  descriptor = -1 # Never retry an interrupted close against a potentially reused descriptor number.
  if posix.close(closing) != 0:
    return AtomicFileError.IoFailure # Report the close refusal before publication.
  var destination = path
  if replace:
    if replaceFile(temporaryName, destination.toCString()) != 0:
      return AtomicFileError.IoFailure # The prior destination remains published on ordinary rename refusal.
  else:
    # Hard-link publication creates exactly one new name atomically; an existing inode or symlink is never replaced.
    if posix.link(temporaryName, destination.toCString()) != 0:
      return if errno() == EEXIST: AtomicFileError.Busy else: AtomicFileError.IoFailure
    if posix.unlink(temporaryName) != 0:
      return AtomicFileError.PublishedUnsynced # The complete destination is already visible even if sibling cleanup failed.
  renamed = true
  if synchronize(directory) != 0:
    return AtomicFileError.PublishedUnsynced # New complete bytes are visible, but durability must not be claimed.
  AtomicFileError.None

proc replaceAtomicFile*(path: string, bytes: openArray[byte], limit: ByteLimit): AtomicFileError =
  ## Atomically replace an explicitly authorized target after syncing complete bytes; preserve existing replacement semantics.
  publishAtomicFile(path, bytes, limit, true)
proc createAtomicFile*(path: string, bytes: openArray[byte], limit: ByteLimit): AtomicFileError =
  ## Publish a new synced file without clobbering any existing file, directory or symlink; an occupied name returns Busy.
  publishAtomicFile(path, bytes, limit, false)

proc syncAtomicFile*(path: string): AtomicFileError =
  ## Confirm an already visible regular file and its parent directory before a caller reuses older transaction data.
  if path.len == 0 or path.len > high(int) - 16:
    return AtomicFileError.InvalidPath # Preserve the shared native path admission contract without suffix allocation.
  for character in path:
    if character == char(0): return AtomicFileError.InvalidPath # The synced identity must match the caller's complete path.
  var nativePath = path
  var descriptor = openDescriptor(nativePath.toCString(), O_RDONLY or O_CLOEXEC or O_NONBLOCK)
  if descriptor < 0: return AtomicFileError.IoFailure
  defer:
    if descriptor >= 0: discard posix.close(descriptor) # Every kind/sync refusal retires this exact opened descriptor once.
  var metadata = default(Stat)
  if posix.fstat(descriptor, metadata) != 0 or not S_ISREG(metadata.st_mode):
    return AtomicFileError.IoFailure # Never block on or claim persistence for a directory, pipe or device.
  if synchronize(descriptor) != 0: return AtomicFileError.IoFailure # No pathname or content is replaced by this recovery operation.
  let closing = descriptor
  descriptor = -1 # Interrupted close cannot justify a retry on a reused descriptor number.
  if posix.close(closing) != 0: return AtomicFileError.IoFailure
  var directoryPath = parent(path)
  var directory = openDescriptor(directoryPath.toCString(), O_RDONLY or O_CLOEXEC or O_NONBLOCK)
  if directory < 0: return AtomicFileError.IoFailure
  defer:
    if directory >= 0: discard posix.close(directory) # Directory-kind/sync failures still retire the native handle.
  var directoryMetadata = default(Stat)
  if posix.fstat(directory, directoryMetadata) != 0 or not S_ISDIR(directoryMetadata.st_mode):
    return AtomicFileError.IoFailure # Only an actual parent directory can establish namespace durability.
  if synchronize(directory) != 0: return AtomicFileError.IoFailure # Visible content is not a completed recovery boundary until the parent syncs too.
  let closingDirectory = directory
  directory = -1 # Retire once before authorizing success.
  if posix.close(closingDirectory) != 0: return AtomicFileError.IoFailure
  AtomicFileError.None
