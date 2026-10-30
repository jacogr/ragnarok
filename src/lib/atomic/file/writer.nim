# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive raw file publication ownership uses a stable advisory lock inode and explicit retirement.
## One host thread serializes each owner; cooperating processes must preserve the .lock file.

import std/assertions
import std/posix/posix
import ../file as atomic_file
import ../../../codec/bounded

type AtomicFileWriter* = object ## Own one lock descriptor and copied destination; no application graph is retained between calls.
  path: string
  descriptor: cint
  active: bool

proc `=copy`*(destination: var AtomicFileWriter, source: AtomicFileWriter) {.error.}
  ## Two handles must not claim the same descriptor/unlock obligation.

proc `=dup`*(source: AtomicFileWriter): AtomicFileWriter {.error.}
  ## Explicit composite exclusivity survives actual ARC ownership lowering.

proc requireClosed(writer: AtomicFileWriter) {.requires: not writer.active.} =
  ## Forgetting explicit retirement cannot silently leak a live publication lock.
  discard

proc `=wasMoved`*(writer: var AtomicFileWriter) {.nodestroy, inline.} =
  ## Transfer cleanup authority without releasing native resources or moved managed fields.
  writer.active = false
  writer.descriptor = -1
  `=wasMoved`(writer.path)

proc `=destroy`*(writer: AtomicFileWriter) =
  ## Caller closes while its lifecycle is still controlled; managed destination bytes then retire normally.
  requireClosed(writer)
  `=destroy`(writer.path)

let noFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
let exclusive {.importc: "LOCK_EX", header: "<sys/file.h>".}: cint
let nonblocking {.importc: "LOCK_NB", header: "<sys/file.h>".}: cint
let unlock {.importc: "LOCK_UN", header: "<sys/file.h>".}: cint
let wouldBlock {.importc: "EWOULDBLOCK", header: "<errno.h>".}: cint
let again {.importc: "EAGAIN", header: "<errno.h>".}: cint

proc openLock(path: cstring, flags, mode: cint): cint {.importc: "open", cdecl,
    header: "<fcntl.h>".}
  ## The real variadic SDK declaration places mode correctly on Darwin ARM64; do not use a fixed-arity libc prototype.

proc lock(fd, operation: cint): cint {.importc: "flock", cdecl, header: "<sys/file.h>".}
  ## Standard OS advisory locks arbitrate independently opened descriptors without blocking the caller.

func opened*(writer: AtomicFileWriter): bool =
  ## Observe only native ownership, without exposing its descriptor or destination storage.
  writer.active

proc openAtomicFileWriter*(writer: var AtomicFileWriter, path: string): AtomicFileError =
  ## Acquire the stable sibling lock before owning a copied destination; failure leaves an inactive owner unchanged.
  if writer.active: return AtomicFileError.Busy # A live owner cannot silently change its publication namespace.
  if path.len == 0 or path.len > high(int) - 16:
    return AtomicFileError.InvalidPath # Prove all native path suffix arithmetic before constructing strings.
  for character in path:
    if character == char(0): return AtomicFileError.InvalidPath # A C path cannot truncate the caller's intended identity.
  var lockPath = path & ".lock"
  let descriptor = openLock(lockPath.toCString(), O_RDWR or O_CREAT or O_CLOEXEC or O_NONBLOCK or
      noFollow, 0o600)
  if descriptor < 0: return AtomicFileError.IoFailure
  var metadata = default(Stat)
  if posix.fstat(descriptor, metadata) != 0 or not S_ISREG(metadata.st_mode):
    discard posix.close(descriptor)
    return AtomicFileError.IoFailure # Only a stable regular inode may arbitrate cooperative publication; FIFO/device locks cannot block or become live owners.
  if lock(descriptor, exclusive or nonblocking) != 0:
    let reason = posix.errno() # Closing must not overwrite the actual contention diagnostic.
    discard posix.close(descriptor)
    if reason == wouldBlock or reason == again: return AtomicFileError.Busy
    return AtomicFileError.IoFailure # Unsupported/failed locking cannot authorize publication.
  writer.path = ""
  for character in path:
    writer.path.add(character) # Own independent bytes even when callers later mutate their source path.
  writer.descriptor = descriptor
  writer.active = true
  AtomicFileError.None

proc close*(writer: var AtomicFileWriter): AtomicFileError =
  ## Idempotently unlock/close once; never unlink the lock inode or retry a possibly reused descriptor.
  if not writer.active: return AtomicFileError.None
  let descriptor = writer.descriptor
  writer.active = false
  writer.descriptor = -1
  writer.path = ""
  let released = lock(descriptor, unlock)
  let closed = posix.close(descriptor)
  if released != 0 or closed != 0: return AtomicFileError.IoFailure # The caller must handle an OS retirement error conservatively.
  AtomicFileError.None

proc replace*(writer: var AtomicFileWriter, bytes: openArray[byte],
    limit: ByteLimit): AtomicFileError =
  ## Publish exact raw bytes only while the cooperative namespace lock is active.
  if not writer.active: return AtomicFileError.Uninitialized # No inactive owner authorizes I/O.
  replaceAtomicFile(writer.path, bytes, limit)

proc read*(writer: var AtomicFileWriter, limit: ByteLimit): BoundedFileResult =
  ## Return owned bounded EOF bytes without imposing a state/control-record schema.
  if not writer.active: return default(BoundedFileResult) # Default/closed reads expose no successful prefix.
  readBoundedFile(writer.path, limit)

proc synchronize*(writer: var AtomicFileWriter): AtomicFileError =
  ## While holding cooperative exclusion, establish durability of the currently visible complete file and parent.
  if not writer.active: return AtomicFileError.Uninitialized # Default/closed owners cannot authorize a recovery boundary.
  syncAtomicFile(writer.path)
