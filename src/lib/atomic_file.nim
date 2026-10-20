# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Synchronous bounded atomic byte publication preserves exact caller bytes and explicit durability outcomes.
## Callers serialize writers, keep the directory namespace stable and retain immutable input through the call.

import std/posix/posix
import ../codec/bounded

type AtomicFileError* {.pure.} = enum ## Success is explicit; visible-but-unsynced publication never becomes None.
  Uninitialized, None, InvalidPath, IoFailure, LimitExceeded, PublishedUnsynced

proc openDirectory(path: cstring, flags: cint): cint {.importc: "open", cdecl, header: "<fcntl.h>".}
  ## The SDK supplies open's actual variadic ABI; directory reads require only its two mandatory arguments.

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

proc replaceAtomicFile*(path: string, bytes: openArray[byte],
    limit: ByteLimit): AtomicFileError =
  ## Preflight path and complete payload before creating a sibling; perform file-sync/rename/directory-sync.
  if path.len == 0 or path.len > high(int) - 16:
    return AtomicFileError.InvalidPath # Prove suffix arithmetic before any owned path construction.
  for character in path:
    if character == char(0): return AtomicFileError.InvalidPath # A C path must preserve the caller's exact destination identity.
  if uint64(bytes.len) > uint64(limit): return AtomicFileError.LimitExceeded # No filesystem resource exists before complete payload admission.
  var directoryPath = parent(path)
  let directory = openDirectory(directoryPath.toCString(), O_RDONLY)
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
  if replaceFile(temporaryName, destination.toCString()) != 0:
    return AtomicFileError.IoFailure # The prior destination remains published on ordinary rename refusal.
  renamed = true
  if synchronize(directory) != 0:
    return AtomicFileError.PublishedUnsynced # New complete bytes are visible, but durability must not be claimed.
  AtomicFileError.None
