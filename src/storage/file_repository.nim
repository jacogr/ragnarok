# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Locked append-only physical node journals publish complete checked revisions after synchronization.
## IO is synchronous startup/storage work; callers preserve the directory and journal inode namespace.

import std/assertions
import std/posix/posix
import ./[node_repository, node_records, record_codec, journal_codec, database_identity, durability]
import ../codec/[bounded, state_trie]

type
  JournalLimits* = object ## Bound complete/accumulated node storage and the whole physical journal.
    repository*: RepositoryLimits
    bytes*: ByteLimit
  FileError* {.pure.} = enum ## Partial/uncertain writes never expose a successful successor view.
    Uninitialized, None, Busy, InvalidPath, AlreadyExists, IoFailure, LimitExceeded,
    WrongIdentity, InvalidJournal, InvalidBatch, InvalidFrame, PublishedUnsynced, RecoveryRequired,
      BackendFailure, RecoveryMismatch
  FileResult*[T] = object ## Guarded alternatives retain precise selected preparation diagnostics.
    case status: FileError
    of None: completed: T
    of InvalidBatch: batchReason: RepositoryResult[RepositoryView]
    of InvalidFrame: frameReason: FrameError
    else: discard
  FileRepository* = object ## Exclusive regular-inode lock and explicit descriptor retirement obligations.
    descriptor, directory: cint
    active, poisoned: bool
    size: uint64
    limits: JournalLimits
    memory: NodeRepository

proc `=copy`*(destination: var FileRepository, source: FileRepository) {.error.}
  ## A file descriptor and its cooperative lock may have only one retirement owner.
proc `=dup`*(source: FileRepository): FileRepository {.error.}
  ## Actual ARC lowering must reject implicit duplication of the composite resource.
proc requireClosed(repository: FileRepository) {.requires: not repository.active.} =
  ## Explicit close is required while native errors can still be handled by the caller.
  discard
proc `=destroy`*(repository: FileRepository) =
  ## Check native retirement before the managed immutable memory head is released.
  requireClosed(repository)
  `=destroy`(repository.memory)

let noFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
let exclusive {.importc: "LOCK_EX", header: "<sys/file.h>".}: cint
let nonblocking {.importc: "LOCK_NB", header: "<sys/file.h>".}: cint
let unlock {.importc: "LOCK_UN", header: "<sys/file.h>".}: cint
let wouldBlock {.importc: "EWOULDBLOCK", header: "<errno.h>".}: cint
let again {.importc: "EAGAIN", header: "<errno.h>".}: cint
let exists {.importc: "EEXIST", header: "<errno.h>".}: cint
proc openFile(path: cstring, flags, mode: cint): cint {.importc: "open", cdecl,
    header: "<fcntl.h>".}
  ## The real variadic SDK declaration supplies the platform-correct mode ABI.
proc lock(fd, operation: cint): cint {.importc: "flock", cdecl, header: "<sys/file.h>".}
  ## Standard advisory inode locking arbitrates cooperating processes without waiting.
proc synchronize(fd: cint): cint {.importc: "fsync", cdecl, header: "<unistd.h>".}
  ## Synchronize explicit file/directory descriptors without changing their namespace.

func error*[T](outcome: FileResult[T]): FileError =
  ## Read the outer publication/lifecycle reason alone.
  outcome.status
func value*[T](outcome: FileResult[T]): T {.inline, requires: outcome.status == FileError.None.} =
  ## Extract only successful publication, retained reads or explicit synchronization receipts.
  outcome.completed
func batchFailure*[T](outcome: FileResult[T]): RepositoryResult[RepositoryView] {.requires:
    outcome.status == FileError.InvalidBatch.} =
  ## Preserve an actual failed in-memory preparation without granting its candidate.
  outcome.batchReason
func frameError*[T](outcome: FileResult[T]): FrameError {.requires: outcome.status ==
    FileError.InvalidFrame.} =
  ## Observe only a selected journal encoding failure.
  outcome.frameReason
func opened*(repository: FileRepository): bool =
  ## Inspect lifecycle without exposing descriptors or a mutable memory publication handle.
  repository.active
proc parent(path: string): string =
  ## Resolve the actual parent before opening stable descriptors for the synchronous operation.
  var slash = -1
  for i, character in path:
    if character == '/': slash = i
  if slash < 0: return "." # Bare names use the caller's current directory at open time.
  if slash == 0: return "/"
  path[0..<slash]
proc validPath(path: string): bool =
  ## Refuse empty/C-truncated identities before any native filesystem operation.
  if path.len == 0: return false
  for character in path:
    if character == char(0): return false
  true
proc writeAll(fd: cint, bytes: openArray[byte]): bool =
  ## Bound each write by actual remaining bytes; zero progress or native refusal terminates.
  var offset = 0
  while offset < bytes.len:
    let count = posix.write(fd, cast[pointer](unsafeAddr bytes[offset]), bytes.len-offset)
    if count <= 0 or count > bytes.len-offset: return false
    offset += count
  true
proc readAll(fd: cint, limit: ByteLimit): FileResult[seq[byte]] =
  ## Fixed chunks detect one excess byte without trusting file-size metadata for allocation.
  let maximum = min(uint64(limit), uint64(high(int)))
  var bytes: seq[byte] = @[]
  var buffer = default(array[4096, byte])
  while true:
    let remaining = maximum-uint64(bytes.len)
    let requested = int(min(remaining, 4095'u64))+1
    let count = posix.read(fd, addr buffer[0], requested)
    if count < 0: return FileResult[seq[byte]](status: FileError.IoFailure)
    if count == 0: break # Only regular-file EOF authorizes a complete byte sequence.
    if uint64(count) > remaining: return FileResult[seq[byte]](status: FileError.LimitExceeded)
    for i in 0..<count: bytes.add(buffer[i])
  FileResult[seq[byte]](status: FileError.None, completed: bytes)
proc truncateFile(fd: cint, extent: int64): cint {.importc: "ftruncate", cdecl,
    header: "<unistd.h>".}
  ## Supported native Linux/macOS SDKs use 64-bit off_t; host-bounded extents are proved before conversion.
proc incompleteTail(bytes: openArray[byte], offset: int, limit: ByteLimit): bool =
  ## Admit only an incomplete final frame, never a complete corrupt frame or oversized length attack.
  let remaining = bytes.len-offset
  if remaining < 8: return true # A torn length prefix cannot be decoded but can be explicitly discarded.
  var length = 0'u64
  for i in 0..<8: length = length or (uint64(bytes[offset+i]) shl (8*i))
  let maximum = min(uint64(limit), uint64(high(int)))
  if maximum < 48 or length < uint64(TrieExportHeaderBytes) or length > maximum-48:
    return false # Unknown/impossible complete lengths require operator investigation, not truncation.
  length+48 > uint64(remaining)

proc acquire(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits, create: bool, repair = false,
    expectedGeneration = RepositoryGeneration(0), expectedRoot = default(StateRoot)): FileError =
  ## Own no resources on failure; adoption follows shape/chain/graph and synchronization checks.
  if repository.active: return FileError.Busy
  if not validPath(path): return FileError.InvalidPath
  if uint64(limits.bytes) < uint64(StorageIdentityBytes): return FileError.LimitExceeded
  var identityBytes: seq[byte] = @[]
  if create:
    let encoded = encodeDatabaseIdentity(fullStateIdentity(chain), limits.bytes)
    if encoded.error == IdentityError.BackendFailure: return FileError.BackendFailure
    if encoded.error != IdentityError.None: return FileError.WrongIdentity
    identityBytes = encoded.value # Validate bootstrap bytes before creating any filesystem resource.
  var nativePath = path
  let flags = O_RDWR or O_APPEND or O_CLOEXEC or O_NONBLOCK or noFollow
  var descriptor = openFile(nativePath.toCString(),
    flags or (if create: O_CREAT or O_EXCL else: 0), 0o600)
  if descriptor < 0:
    if create and posix.errno() == exists: return FileError.AlreadyExists
    return FileError.IoFailure
  var directory = -1.cint
  var locked = false
  defer:
    if descriptor >= 0:
      if locked: discard lock(descriptor, unlock) # Every refused open releases its own cooperative lock.
      discard posix.close(descriptor)
    if directory >= 0: discard posix.close(directory)
  var metadata = default(Stat)
  if posix.fstat(descriptor, metadata) != 0 or not S_ISREG(
      metadata.st_mode): return FileError.IoFailure
  if lock(descriptor, exclusive or nonblocking) != 0:
    let reason = posix.errno()
    if reason == wouldBlock or reason == again: return FileError.Busy
    return FileError.IoFailure
  locked = true
  var directoryPath = parent(path)
  directory = openFile(directoryPath.toCString(), O_RDONLY or O_CLOEXEC or O_NONBLOCK, 0)
  if directory < 0: return FileError.IoFailure
  var directoryMetadata = default(Stat)
  if posix.fstat(directory, directoryMetadata) != 0 or not S_ISDIR(
      directoryMetadata.st_mode): return FileError.IoFailure
  var memory = newNodeRepository(limits.repository)
  var size = 0'u64
  if create:
    if not writeAll(descriptor, identityBytes): return FileError.IoFailure
    size = uint64(identityBytes.len) # Failed initialization preserves its file for explicit operator recovery.
  else:
    let loaded = readAll(descriptor, limits.bytes)
    if loaded.error != FileError.None: return loaded.error
    let bytes = loaded.value
    if bytes.len < StorageIdentityBytes: return FileError.WrongIdentity
    let identity = decodeDatabaseIdentity(bytes.toOpenArray(0, StorageIdentityBytes-1), chain,
      ByteLimit(StorageIdentityBytes))
    if identity.error == IdentityError.BackendFailure: return FileError.BackendFailure
    if identity.error != IdentityError.None: return FileError.WrongIdentity
    var offset = StorageIdentityBytes
    var partial = false
    while offset < bytes.len:
      let extent = journalFrameExtent(bytes.toOpenArray(offset, bytes.high), limits.bytes)
      if extent.error != FrameError.None:
        if repair and incompleteTail(bytes, offset, limits.bytes):
          partial = true
          break # Only explicit recovery can stop at a verified prefix preceding an incomplete final frame.
        return FileError.InvalidJournal
      let frame = decodeJournalFrame(bytes.toOpenArray(offset, offset+extent.value-1),
        limits.repository.codec, limits.bytes)
      if frame.error == FrameError.BackendFailure: return FileError.BackendFailure
      if frame.error != FrameError.None: return FileError.InvalidJournal
      let current = memory.snapshot.value
      if uint64(current.generation) == high(uint64) or
          uint64(frame.value.generation) != uint64(current.generation)+1:
        return FileError.InvalidJournal
      if memory.publish(current, frame.value.batch).error !=
          RepositoryError.None: return FileError.InvalidJournal
      offset += extent.value # Extent validation proved exact bounded forward progress.
    if repair:
      let selected = memory.snapshot.value
      if uint64(selected.generation) != uint64(expectedGeneration) or
          array[32, byte](selected.commitment.root) != array[32, byte](expectedRoot):
        return FileError.RecoveryMismatch # An independent exact prefix token is required before any destructive operation.
      if partial:
        if synchronize(descriptor) != 0 or synchronize(directory) != 0: return FileError.IoFailure
        if truncateFile(descriptor, int64(offset)) != 0: return FileError.IoFailure
        size = uint64(offset) # O_APPEND makes the next write start at the truncated EOF despite the old read offset.
      else:
        size = uint64(bytes.len) # A complete visible frame cannot be discarded to satisfy an older token.
    else:
      size = uint64(bytes.len)
  if synchronize(descriptor) != 0 or synchronize(directory) != 0: return FileError.IoFailure
  repository.descriptor = descriptor
  repository.directory = directory
  repository.memory = memory
  repository.limits = limits
  repository.size = size
  repository.poisoned = false
  repository.active = true # No live owner is published before the visible journal is durably anchored.
  descriptor = -1
  directory = -1
  FileError.None
proc initializeFileRepository*(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits): FileError =
  ## Explicitly create an absent full-state journal; existing files are never reset or converted.
  acquire(repository, path, chain, limits, true)
proc openFileRepository*(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits): FileError =
  ## Strictly reopen every complete frame with the independently selected chain and new ceilings.
  acquire(repository, path, chain, limits, false)
proc recoverFileRepository*(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits, expectedGeneration: RepositoryGeneration,
        expectedRoot: StateRoot): FileError =
  ## Explicitly truncate only an incomplete final append after independently verifying its exact durable prefix.
  acquire(repository, path, chain, limits, false, true, expectedGeneration, expectedRoot)
proc snapshot*(repository: FileRepository): FileResult[RepositoryView] =
  ## Uncertain/partial publication requires reopening or explicit recovery before new reads.
  if not repository.active: return FileResult[RepositoryView](status: FileError.Uninitialized)
  if repository.poisoned: return FileResult[RepositoryView](status: FileError.RecoveryRequired)
  FileResult[RepositoryView](status: FileError.None, completed: repository.memory.snapshot.value)
proc close*(repository: var FileRepository): FileError =
  ## Disarm native ownership once and never retry potentially reused descriptors.
  if not repository.active: return FileError.Uninitialized
  let descriptor = repository.descriptor
  let directory = repository.directory
  repository.active = false
  repository.descriptor = -1
  repository.directory = -1
  discard repository.memory.close
  let released = lock(descriptor, unlock)
  let retired = posix.close(descriptor)
  let parentRetired = posix.close(directory)
  if released != 0 or retired != 0 or parentRetired != 0: return FileError.IoFailure
  FileError.None
proc publish*(repository: var FileRepository, expected: RepositoryView,
    batch: TrieExport): FileResult[RepositoryView] =
  ## Prepare privately, bound physical growth, append/sync, then adopt the exact prepared view.
  if not repository.active: return FileResult[RepositoryView](status: FileError.Uninitialized)
  if repository.poisoned: return FileResult[RepositoryView](status: FileError.RecoveryRequired)
  var working = repository.memory
  let prepared = working.publish(expected, batch)
  if prepared.error != RepositoryError.None:
    return FileResult[RepositoryView](status: FileError.InvalidBatch, batchReason: prepared)
  let maximum = min(uint64(repository.limits.bytes), uint64(high(int)))
  let remaining = maximum-repository.size
  let frame = encodeJournalFrame(prepared.value.generation, batch,
    repository.limits.repository.codec, ByteLimit(remaining))
  if frame.error == FrameError.LimitExceeded: return FileResult[RepositoryView](
      status: FileError.LimitExceeded)
  if frame.error != FrameError.None:
    return FileResult[RepositoryView](status: FileError.InvalidFrame, frameReason: frame.error)
  if synchronize(repository.descriptor) != 0 or synchronize(repository.directory) != 0:
    repository.poisoned = true
    return FileResult[RepositoryView](status: FileError.IoFailure) # Reuse never follows an unconfirmed old durable boundary.
  if not writeAll(repository.descriptor, frame.value):
    repository.poisoned = true
    return FileResult[RepositoryView](status: FileError.IoFailure) # A partial tail has no selected candidate.
  repository.size += uint64(frame.value.len) # Remaining-capacity preflight proved this exact addition.
  if synchronize(repository.descriptor) != 0:
    repository.poisoned = true
    return FileResult[RepositoryView](status: FileError.PublishedUnsynced) # Complete bytes may be visible, but no successor is authorized.
  repository.memory = working # This is the only live head replacement, after full durable publication.
  FileResult[RepositoryView](status: FileError.None, completed: prepared.value)

proc synchronize*(repository: var FileRepository): FileResult[StorageDurability] =
  ## Confirm the current file and directory boundary; uncertainty poisons further live operations.
  if not repository.active: return FileResult[StorageDurability](status: FileError.Uninitialized)
  if repository.poisoned: return FileResult[StorageDurability](status: FileError.RecoveryRequired)
  if synchronize(repository.descriptor) != 0 or synchronize(repository.directory) != 0:
    repository.poisoned = true
    return FileResult[StorageDurability](status: FileError.IoFailure)
  FileResult[StorageDurability](status: FileError.None,
    completed: StorageDurability.FileAndDirectorySynced)
