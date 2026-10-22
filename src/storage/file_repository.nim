# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Locked append-only physical node journals publish complete checked revisions after synchronization.
## IO is synchronous startup/storage work; callers preserve the directory and journal inode namespace.

import ./[file_errors, managed_repository, managed_manifest]
export file_errors

import std/assertions
import std/posix/posix
import ./[node_repository, node_records, record_codec, journal_codec, database_identity, durability]
import ../codec/[bounded, state_trie]

type
  JournalLimits* = object ## Bound complete/accumulated node storage and the whole physical journal.
    repository*: RepositoryLimits
    bytes*: ByteLimit
    contextBytes*: ByteLimit # Independent per-frame application metadata ceiling; zero for node-only journals.
  FileResult*[T] = object ## Guarded alternatives retain precise selected preparation diagnostics.
    case status: FileError
    of None: completed: T
    of InvalidBatch: batchReason: RepositoryResult[RepositoryView]
    of InvalidFrame: frameReason: FrameError
    else: discard
  FileRepository* = object ## Exclusive regular-inode lock and explicit descriptor retirement obligations.
    managed: ManagedRepository
    managedMode: bool
    descriptor, directory: cint
    active, poisoned: bool
    size: uint64
    limits: JournalLimits
    memory: NodeRepository
    chain: StorageChainId
    schema: StorageSchema
    context: seq[byte] # Private selected bytes advance only with their durable memory revision.

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
  `=destroy`(repository.managed)
  `=destroy`(repository.memory)
  `=destroy`(repository.context)

let noFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
let exclusive {.importc: "LOCK_EX", header: "<sys/file.h>".}: cint
let nonblocking {.importc: "LOCK_NB", header: "<sys/file.h>".}: cint
let unlock {.importc: "LOCK_UN", header: "<sys/file.h>".}: cint
let wouldBlock {.importc: "EWOULDBLOCK", header: "<errno.h>".}: cint
let again {.importc: "EAGAIN", header: "<errno.h>".}: cint
let interrupted {.importc: "EINTR", header: "<errno.h>".}: cint
let exists {.importc: "EEXIST", header: "<errno.h>".}: cint
proc closeNative(fd: cint): cint {.importc: "close", cdecl, header: "<unistd.h>".}
  ## Retire a descriptor once through its SDK declaration; even EINTR must never cause a retry.
proc openFile(path: cstring, flags, mode: cint): cint {.importc: "open", cdecl,
    header: "<fcntl.h>".}
  ## The real variadic SDK declaration supplies the platform-correct mode ABI.
proc lockNative(fd, operation: cint): cint {.importc: "flock", cdecl, header: "<sys/file.h>".}
  ## Standard advisory inode locking arbitrates cooperating processes without waiting.
proc lock(fd, operation: cint): cint =
  ## Retry only interrupted operations on the same descriptor; the existing nonblocking flags are unchanged.
  while true:
    let status = lockNative(fd, operation)
    if status == 0 or posix.errno() != interrupted: return status
    # Busy and permanent refusal return immediately; an interrupted unlock still owns this live descriptor.
proc syncNative(fd: cint): cint {.importc: "fsync", cdecl, header: "<unistd.h>".}
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
proc synchronize(fd: cint): cint =
  ## Retry an interrupted barrier on the same live descriptor; permanent refusal remains uncertain IO.
  while true:
    let status = syncNative(fd)
    if status == 0 or posix.errno() != interrupted: return status
    # EINTR confirms no durability receipt; another real barrier must complete before success.

proc managedOutcome[T](outcome: ManagedResult[T]): FileResult[T] =
  ## Translate only checked alternatives into this facade's private result domain.
  case outcome.error
  of FileError.None: FileResult[T](status: FileError.None, completed: outcome.value)
  of FileError.InvalidBatch: FileResult[T](status: FileError.InvalidBatch,
      batchReason: outcome.batchFailure)
  of FileError.InvalidFrame: FileResult[T](status: FileError.InvalidFrame,
      frameReason: outcome.frameError)
  else: FileResult[T](status: outcome.error)
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
proc writeNative(fd: cint, buffer: pointer, count: csize_t): clong {.importc: "write", cdecl,
    header: "<unistd.h>".}
  ## SDK-header binding preserves signed-long ssize_t results and bounded size_t input extents.
proc writeAll(fd: cint, bytes: openArray[byte]): bool =
  ## Bound each write by actual remaining bytes; zero progress or native refusal terminates.
  var offset = 0
  while offset < bytes.len:
    let count = writeNative(fd, cast[pointer](unsafeAddr bytes[offset]), csize_t(bytes.len-offset))
    if count < 0 and posix.errno() == interrupted:
      continue # No bytes transferred; retain the offset established by earlier real progress.
    if count <= 0 or count > bytes.len-offset: return false
    offset += count
  true
proc readNative(fd: cint, buffer: pointer, count: csize_t): clong {.importc: "read", cdecl,
    header: "<unistd.h>".}
  ## Supported Linux/macOS SDKs return signed-long ssize_t; explicit headers preserve the native ABI.
proc readAll(fd: cint, limit: ByteLimit): FileResult[seq[byte]] =
  ## Fixed chunks detect one excess byte without trusting file-size metadata for allocation.
  let maximum = min(uint64(limit), uint64(high(int)))
  var bytes: seq[byte] = @[]
  var buffer = default(array[4096, byte])
  while true:
    let remaining = maximum-uint64(bytes.len)
    let requested = int(min(remaining, 4095'u64))+1
    let count = readNative(fd, addr buffer[0], csize_t(requested))
    if count < 0:
      if posix.errno() == interrupted: continue # Interrupted reads transfer no bytes; retry the same bounded extent.
      return FileResult[seq[byte]](status: FileError.IoFailure)
    if count == 0: break # Only regular-file EOF authorizes a complete byte sequence.
    if uint64(count) > remaining: return FileResult[seq[byte]](status: FileError.LimitExceeded)
    for i in 0..<count: bytes.add(buffer[i])
  FileResult[seq[byte]](status: FileError.None, completed: bytes)
proc truncateNative(fd: cint, extent: int64): cint {.importc: "ftruncate", cdecl,
    header: "<unistd.h>".}
  ## Supported native Linux/macOS SDKs use 64-bit off_t; host-bounded extents are proved before conversion.
proc truncateFile(fd: cint, extent: int64): cint =
  ## Retry only EINTR on the same already-authorized extent; repeating that truncation is idempotent.
  while true:
    let status = truncateNative(fd, extent)
    if status == 0 or posix.errno() != interrupted: return status
    # No new generation/root or extent can be chosen while this native owner holds the lease.
proc incompleteTail(bytes: openArray[byte], offset: int, limit: ByteLimit, contextual: bool): bool =
  ## Admit only an incomplete final frame, never a complete corrupt frame or oversized length attack.
  let remaining = bytes.len-offset
  if remaining < 8: return true # A torn length prefix cannot be decoded but can be explicitly discarded.
  var length = 0'u64
  for i in 0..<8: length = length or (uint64(bytes[offset+i]) shl (8*i))
  let maximum = min(uint64(limit), uint64(high(int)))
  let minimumBody = uint64(TrieExportHeaderBytes)+(if contextual: 8'u64 else: 0'u64)
  if maximum < 48 or length < minimumBody or length > maximum-48:
    return false # Unknown/impossible complete lengths require operator investigation, not truncation.
  length+48 > uint64(remaining)

proc acquire(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits, create: bool, repair = false,
    expectedGeneration = RepositoryGeneration(0), expectedRoot = default(StateRoot),
    schema = StorageSchema.FullNodesV1): FileError =
  ## Own no resources on failure; adoption follows shape/chain/graph and synchronization checks.
  if repository.active: return FileError.Busy
  if not validPath(path): return FileError.InvalidPath
  if uint64(limits.bytes) < uint64(StorageIdentityBytes): return FileError.LimitExceeded
  var identityBytes: seq[byte] = @[]
  if create:
    let encoded = encodeDatabaseIdentity(fullStateIdentity(chain, schema), limits.bytes)
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
      discard closeNative(descriptor)
    if directory >= 0: discard closeNative(directory)
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
  var context: seq[byte] = @[]
  if create:
    if not writeAll(descriptor, identityBytes): return FileError.IoFailure
    size = uint64(identityBytes.len) # Failed initialization preserves its file for explicit operator recovery.
  else:
    let loaded = readAll(descriptor, limits.bytes)
    if loaded.error != FileError.None: return loaded.error
    let bytes = loaded.value
    if bytes.len < StorageIdentityBytes: return FileError.WrongIdentity
    let identity = decodeDatabaseIdentity(bytes.toOpenArray(0, StorageIdentityBytes-1), chain,
      ByteLimit(StorageIdentityBytes), schema)
    if identity.error == IdentityError.BackendFailure: return FileError.BackendFailure
    if identity.error != IdentityError.None: return FileError.WrongIdentity
    var offset = StorageIdentityBytes
    var partial = false
    while offset < bytes.len:
      let extent = journalFrameExtent(bytes.toOpenArray(offset, bytes.high), limits.bytes)
      if extent.error != FrameError.None:
        if repair and incompleteTail(bytes, offset, limits.bytes, schema ==
            StorageSchema.FullStateV1):
          partial = true
          break # Only explicit recovery can stop at a verified prefix preceding an incomplete final frame.
        return FileError.InvalidJournal
      let current = memory.snapshot.value
      let frame = if schema == StorageSchema.FullStateV1:
        memory.replayContextJournalFrame(current, bytes.toOpenArray(offset, offset+extent.value-1),
          limits.contextBytes, limits.bytes)
      else:
        memory.replayJournalFrame(current, bytes.toOpenArray(offset, offset+extent.value-1),
          limits.bytes) # Schema is independently selected before checksum and atomic graph admission.
      if frame.error == FrameError.BackendFailure: return FileError.BackendFailure
      if frame.error != FrameError.None: return FileError.InvalidJournal
      context = frame.value.context # Only a fully admitted frame can select its context.
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
  repository.managedMode = false
  repository.descriptor = descriptor
  repository.directory = directory
  repository.memory = memory
  repository.chain = chain
  repository.schema = schema
  repository.context = context
  repository.limits = limits
  repository.size = size
  repository.poisoned = false
  repository.active = true # No live owner is published before the visible journal is durably anchored.
  descriptor = -1
  directory = -1
  FileError.None
proc initializeFileRepository*(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits, schema = StorageSchema.FullNodesV1): FileError =
  ## Explicitly create an absent full-state journal; existing files are never reset or converted.
  acquire(repository, path, chain, limits, true, schema = schema)
proc openFileRepository*(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits, schema = StorageSchema.FullNodesV1): FileError =
  ## Strictly reopen every complete frame with the independently selected chain and new ceilings.
  acquire(repository, path, chain, limits, false, schema = schema)
proc recoverFileRepository*(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: JournalLimits, expectedGeneration: RepositoryGeneration,
        expectedRoot: StateRoot, schema = StorageSchema.FullNodesV1): FileError =
  ## Explicitly truncate only an incomplete final append after independently verifying its exact durable prefix.
  acquire(repository, path, chain, limits, false, true, expectedGeneration, expectedRoot, schema)
proc snapshot*(repository: FileRepository): FileResult[RepositoryView] =
  ## Uncertain/partial publication requires reopening or explicit recovery before new reads.
  if repository.managedMode: return managedOutcome(repository.managed.snapshot)
  if not repository.active: return FileResult[RepositoryView](status: FileError.Uninitialized)
  if repository.poisoned: return FileResult[RepositoryView](status: FileError.RecoveryRequired)
  FileResult[RepositoryView](status: FileError.None, completed: repository.memory.snapshot.value)
proc close*(repository: var FileRepository): FileError =
  ## Disarm native ownership once and never retry potentially reused descriptors.
  if repository.managedMode:
    repository.active = false
    return repository.managed.close
  if not repository.active: return FileError.Uninitialized
  let descriptor = repository.descriptor
  let directory = repository.directory
  repository.active = false
  repository.descriptor = -1
  repository.directory = -1
  discard repository.memory.close
  repository.context = @[] # Retained detached contexts have their own byte owners.
  let released = lock(descriptor, unlock)
  let retired = closeNative(descriptor)
  let parentRetired = closeNative(directory)
  if released != 0 or retired != 0 or parentRetired != 0: return FileError.IoFailure
  FileError.None
proc publish*(repository: var FileRepository, expected: RepositoryView,
    batch: TrieExport, context: openArray[byte] = []): FileResult[RepositoryView] =
  ## Prepare privately, bound physical growth, append/sync, then adopt the exact prepared view.
  if repository.managedMode: return managedOutcome(repository.managed.publish(expected, batch, context))
  if not repository.active: return FileResult[RepositoryView](status: FileError.Uninitialized)
  if repository.poisoned: return FileResult[RepositoryView](status: FileError.RecoveryRequired)
  if uint64(context.len) > uint64(repository.limits.contextBytes) or
      (repository.schema == StorageSchema.FullNodesV1 and context.len != 0):
    return FileResult[RepositoryView](status: FileError.LimitExceeded)
  var selectedContext = newSeq[byte](context.len)
  for index, octet in context: selectedContext[index] = octet # Input mutation cannot affect a published context.
  var working = repository.memory
  let prepared = working.publish(expected, batch)
  if prepared.error != RepositoryError.None:
    return FileResult[RepositoryView](status: FileError.InvalidBatch, batchReason: prepared)
  let maximum = min(uint64(repository.limits.bytes), uint64(high(int)))
  let remaining = maximum-repository.size
  let frame = if repository.schema == StorageSchema.FullStateV1:
    encodeContextJournalFrame(prepared.value.generation, batch, selectedContext,
      repository.limits.contextBytes, repository.limits.repository.codec, ByteLimit(remaining))
  else:
    encodeJournalFrame(prepared.value.generation, batch,
      repository.limits.repository.codec, ByteLimit(remaining)) # Node-only publication stays byte-compatible.
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
  repository.context = selectedContext
  repository.memory = working # This is the only live head replacement, after full durable publication.
  FileResult[RepositoryView](status: FileError.None, completed: prepared.value)

proc synchronize*(repository: var FileRepository): FileResult[StorageDurability] =
  ## Confirm the current file and directory boundary; uncertainty poisons further live operations.
  if repository.managedMode: return managedOutcome(repository.managed.synchronize)
  if not repository.active: return FileResult[StorageDurability](status: FileError.Uninitialized)
  if repository.poisoned: return FileResult[StorageDurability](status: FileError.RecoveryRequired)
  if synchronize(repository.descriptor) != 0 or synchronize(repository.directory) != 0:
    repository.poisoned = true
    return FileResult[StorageDurability](status: FileError.IoFailure)
  FileResult[StorageDurability](status: FileError.None,
    completed: StorageDurability.FileAndDirectorySynced)

proc snapshotContext*(repository: FileRepository): FileResult[seq[byte]] =
  ## Return detached context from the same single-threaded selected revision; poison refuses new reads.
  if repository.managedMode: return managedOutcome(repository.managed.snapshotContext)
  if not repository.active: return FileResult[seq[byte]](status: FileError.Uninitialized)
  if repository.poisoned: return FileResult[seq[byte]](status: FileError.RecoveryRequired)
  var bytes = newSeq[byte](repository.context.len)
  for index, octet in repository.context: bytes[index] = octet # No mutable alias to selected metadata escapes.
  FileResult[seq[byte]](status: FileError.None, completed: bytes)

proc chainIdentity*(repository: FileRepository): FileResult[StorageChainId] =
  ## Read only the chain admitted while acquiring this live source; callers cannot rebind migration identity.
  if not repository.active: return FileResult[StorageChainId](status: FileError.Uninitialized)
  let selected = repository.snapshot
  if selected.error != FileError.None: return FileResult[StorageChainId](status: selected.error)
  FileResult[StorageChainId](status: FileError.None, completed: repository.chain)
proc storageSchema*(repository: FileRepository): FileResult[StorageSchema] =
  ## Preserve the source's explicitly selected schema across source-preserving migration.
  if not repository.active: return FileResult[StorageSchema](status: FileError.Uninitialized)
  let selected = repository.snapshot
  if selected.error != FileError.None: return FileResult[StorageSchema](status: selected.error)
  FileResult[StorageSchema](status: FileError.None, completed: repository.schema)
proc adoptManaged(repository: var FileRepository, chain: StorageChainId, limits: ManagedLimits,
    schema: StorageSchema) =
  ## Only an already successful managed acquisition grants this facade's scalar lifecycle metadata.
  repository.chain = chain
  repository.schema = schema
  repository.limits = JournalLimits(repository: limits.repository, bytes: limits.journalBytes,
    contextBytes: limits.contextBytes)
  repository.managedMode = true
  repository.poisoned = false
  repository.active = true
proc initializeManagedFileRepository*(repository: var FileRepository, path: string,
    chain: StorageChainId, selection: RepositorySelection, context: openArray[byte],
    limits: ManagedLimits, schema = StorageSchema.FullNodesV1): FileError =
  ## Explicit managed creation takes a complete seed; legacy empty-file initialization stays unchanged.
  if repository.active: return FileError.Busy
  let reason = initializeManagedRepository(repository.managed, path, chain, selection, context,
      limits, schema)
  if reason != FileError.None: return reason
  adoptManaged(repository, chain, limits, schema)
  FileError.None
proc openManagedFileRepository*(repository: var FileRepository, path: string, chain: StorageChainId,
    limits: ManagedLimits, schema = StorageSchema.FullNodesV1): FileError =
  ## Explicit layout selection never guesses or automatically migrates an existing file.
  if repository.active: return FileError.Busy
  let reason = openManagedRepository(repository.managed, path, chain, limits, schema)
  if reason != FileError.None: return reason
  adoptManaged(repository, chain, limits, schema)
  FileError.None
proc recoverManagedFileRepository*(repository: var FileRepository, path: string,
    chain: StorageChainId, limits: ManagedLimits, expectedGeneration: RepositoryGeneration,
        expectedRoot: StateRoot,
    schema = StorageSchema.FullNodesV1): FileError =
  ## Keep exact-prefix destructive recovery explicit in both layouts.
  if repository.active: return FileError.Busy
  let reason = recoverManagedRepository(repository.managed, path, chain, limits, expectedGeneration,
    expectedRoot, schema)
  if reason != FileError.None: return reason
  adoptManaged(repository, chain, limits, schema)
  FileError.None
proc compact*(repository: var FileRepository, expected: RepositoryView,
    roots: openArray[StateRoot]): FileResult[ManagedCompaction] =
  ## Only explicitly selected managed owners support online physical replacement.
  if not repository.active: return default(FileResult[ManagedCompaction])
  if not repository.managedMode: return FileResult[ManagedCompaction](
      status: FileError.UnsupportedLayout)
  managedOutcome(repository.managed.compact(expected, roots))
proc managedUsage*(repository: FileRepository): FileResult[ManagedUsage] =
  ## Selected-file extents are available only for an explicitly acquired managed layout.
  if not repository.active: return default(FileResult[ManagedUsage])
  if not repository.managedMode: return FileResult[ManagedUsage](
      status: FileError.UnsupportedLayout)
  managedOutcome(repository.managed.usage)

proc discardManagedStaging*(repository: var FileRepository): FileError =
  ## A checked managed owner may remove only pending CURRENT and its immediate unselected successor.
  if not repository.active: return FileError.Uninitialized
  if not repository.managedMode: return FileError.UnsupportedLayout
  repository.managed.discardManagedStaging
proc cleanupRetiredEpoch*(repository: var FileRepository, epoch: ManagedEpoch): FileError =
  ## Explicitly retire one earlier managed pair without scanning or changing the selected revision.
  if not repository.active: return FileError.Uninitialized
  if not repository.managedMode: return FileError.UnsupportedLayout
  repository.managed.cleanupRetiredEpoch(epoch)
