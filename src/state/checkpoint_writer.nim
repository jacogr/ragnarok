# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exclusive checkpoint publication ownership uses a stable advisory lock inode and explicit retirement.
## One host thread serializes each owner; cooperating processes must preserve the .lock file.

import std/assertions
import std/posix/posix
import ./[checkpoint_file, store]
import ../codec/[bounded, state_trie]

type CheckpointWriter* = object ## Own one lock descriptor and copied destination; no canonical graph is retained between calls.
  path: string
  descriptor: cint
  active: bool

proc `=copy`*(destination: var CheckpointWriter, source: CheckpointWriter) {.error.}
  ## Two handles must not claim the same descriptor/unlock obligation.
proc `=dup`*(source: CheckpointWriter): CheckpointWriter {.error.}
  ## Explicit composite exclusivity survives actual ARC ownership lowering.
proc requireClosed(writer: CheckpointWriter) {.requires: not writer.active.} =
  ## Forgetting explicit retirement cannot silently leak a live publication lock.
  discard
proc `=destroy`*(writer: CheckpointWriter) =
  ## Caller closes while its lifecycle is still controlled; managed destination bytes then retire normally.
  requireClosed(writer)
  `=destroy`(writer.path)

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

func opened*(writer: CheckpointWriter): bool =
  ## Observe only native ownership, without exposing its descriptor or destination storage.
  writer.active
proc openCheckpointWriter*(writer: var CheckpointWriter, path: string): CheckpointFileError =
  ## Acquire the stable sibling lock before owning a copied destination; failure leaves an inactive owner unchanged.
  if writer.active: return CheckpointFileError.Busy # A live owner cannot silently change its publication namespace.
  if path.len == 0 or path.len > high(int) - 16:
    return CheckpointFileError.InvalidPath # Prove all native path suffix arithmetic before constructing strings.
  for character in path:
    if character == char(0): return CheckpointFileError.InvalidPath # A C path cannot truncate the caller's intended identity.
  var lockPath = path & ".lock"
  let descriptor = openLock(lockPath.toCString(), O_RDWR or O_CREAT or O_CLOEXEC, 0o600)
  if descriptor < 0: return CheckpointFileError.IoFailure
  if lock(descriptor, exclusive or nonblocking) != 0:
    let reason = posix.errno() # Closing must not overwrite the actual contention diagnostic.
    discard posix.close(descriptor)
    if reason == wouldBlock or reason == again: return CheckpointFileError.Busy
    return CheckpointFileError.IoFailure # Unsupported/failed locking cannot authorize publication.
  writer.path = ""
  for character in path:
    writer.path.add(character) # Own independent bytes even when callers later mutate their source path.
  writer.descriptor = descriptor
  writer.active = true
  CheckpointFileError.None
proc close*(writer: var CheckpointWriter): CheckpointFileError =
  ## Idempotently unlock/close once; never unlink the lock inode or retry a possibly reused descriptor.
  if not writer.active: return CheckpointFileError.None
  let descriptor = writer.descriptor
  writer.active = false
  writer.descriptor = -1
  writer.path = ""
  let released = lock(descriptor, unlock)
  let closed = posix.close(descriptor)
  if released != 0 or closed != 0: return CheckpointFileError.IoFailure # The caller must handle an OS retirement error conservatively.
  CheckpointFileError.None
proc save*(writer: var CheckpointWriter, snapshot: StateStoreSnapshot,
    limit: ByteLimit): CheckpointFileResult[StateStoreSnapshot] =
  ## Publish only while this host owns the cooperative writer lock; canonical authority stays with the caller.
  if not writer.active: return default(CheckpointFileResult[
      StateStoreSnapshot]) # Closed/default owners expose no successful payload.
  saveFullCheckpoint(writer.path, snapshot, limit)
proc load*(writer: var CheckpointWriter, expected: StateRoot, limits: StateStoreLimits,
    limit: ByteLimit): CheckpointFileResult[StateStore] =
  ## Every owner-bound read requires an independently trusted complete root.
  if not writer.active: return default(CheckpointFileResult[
      StateStore]) # Closed/default owners cannot bypass their lifecycle.
  loadFullCheckpoint(writer.path, expected, limits, limit)
