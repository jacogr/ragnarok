# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Stable directory-relative managed storage IO keeps one persistent LOCK inode across file epochs.
## Callers own the directory namespace; no child name comes from untrusted manifest strings.
import std/[assertions]
import std/posix/posix
import ./[file_errors, managed_manifest]
import ../codec/bounded
type
  ManagedFileKind* {.pure.} = enum ## The managed namespace exposes only exact fixed or epoch-derived names.
    Current, Snapshot, Journal
  ManagedIoResult*[T] = object ## Private IO outcomes cannot forge another backend's success payloads.
    case status: FileError
    of None: completed: T
    else: discard
  DirectoryState = ref object ## Stable shared lease state keeps descriptors independent of owner relocation.
    descriptor, lockDescriptor: cint
    active: bool
    journals: int
  ManagedDirectory* = object ## Unique explicit retirement authority; journals retain the stable lease state.
    data: nil DirectoryState
  ManagedJournal* = object ## One append descriptor retains its directory lease until explicit retirement.
    descriptor: cint
    state: nil DirectoryState
    active, poisoned: bool
    size: uint64
    limit: ByteLimit
func opened*(directory: ManagedDirectory): bool =
  ## Inspect lifecycle without exporting the shared native lease state.
  let state = directory.data
  state != nil and state.active
proc nativeDescriptor(directory: ManagedDirectory): cint {.requires: directory.opened.} =
  ## Borrow a scalar descriptor only for the immediate synchronous native operation.
  let state = directory.data
  assert state != nil
  state.descriptor
proc `=copy`*(destination: var ManagedDirectory, source: ManagedDirectory) {.error.}
  ## Native directory/lock retirement has one owner.
proc `=dup`*(source: ManagedDirectory): ManagedDirectory {.error.}
  ## Actual lowering rejects hidden composite resource duplication.
proc requireClosed(directory: ManagedDirectory) {.requires: not directory.opened.} =
  ## Explicit retirement keeps native close failures observable.
  discard
proc `=destroy`*(directory: ManagedDirectory) =
  ## Destruction may not silently abandon the persistent lock.
  requireClosed(directory)
  `=destroy`(directory.data)
let noFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
let directoryFlag {.importc: "O_DIRECTORY", header: "<fcntl.h>".}: cint
let exclusive {.importc: "LOCK_EX", header: "<sys/file.h>".}: cint
let nonblocking {.importc: "LOCK_NB", header: "<sys/file.h>".}: cint
let unlock {.importc: "LOCK_UN", header: "<sys/file.h>".}: cint
let wouldBlock {.importc: "EWOULDBLOCK", header: "<errno.h>".}: cint
let again {.importc: "EAGAIN", header: "<errno.h>".}: cint
let interrupted {.importc: "EINTR", header: "<errno.h>".}: cint
let exists {.importc: "EEXIST", header: "<errno.h>".}: cint
let missing {.importc: "ENOENT", header: "<errno.h>".}: cint
proc openFile(path: cstring, flags, mode: cint): cint {.importc: "open", cdecl,
    header: "<fcntl.h>".}
  ## SDK variadic open preserves platform mode promotion.
proc openAt(directory: cint, path: cstring, flags, mode: cint): cint {.importc: "openat", cdecl,
    header: "<fcntl.h>".}
  ## Resolve every managed child against the held directory, never a repeated parent pathname.
proc makeDirectory(path: cstring, mode: cint): cint {.importc: "mkdir", cdecl,
    header: "<sys/stat.h>".}
  ## Exclusively create one private managed namespace.
proc lockFile(fd, operation: cint): cint {.importc: "flock", cdecl, header: "<sys/file.h>".}
  ## Cooperating processes arbitrate through one persistent inode, without waiting.
proc syncFile(fd: cint): cint {.importc: "fsync", cdecl, header: "<unistd.h>".}
  ## Report both data and namespace durability barriers explicitly.
proc unlinkAt(directory: cint, path: cstring, flags: cint): cint {.importc: "unlinkat", cdecl,
    header: "<unistd.h>".}
  ## Remove only a proved owned child name without following symlinks.
func error*[T](outcome: ManagedIoResult[T]): FileError =
  ## Observe the shared typed native refusal without exposing result storage.
  outcome.status
func value*[T](outcome: ManagedIoResult[T]): T {.inline, requires: outcome.status ==
    FileError.None.} =
  ## Extract only complete successful IO bytes or canonical names.
  outcome.completed
proc managedFileName*(kind: ManagedFileKind, epoch: ManagedEpoch): ManagedIoResult[string] =
  ## Derive canonical lowercase hexadecimal epoch names; CURRENT has no variable path component.
  if kind == ManagedFileKind.Current:
    return ManagedIoResult[string](status: FileError.None, completed: "CURRENT")
  if kind notin {ManagedFileKind.Snapshot, ManagedFileKind.Journal} or uint64(epoch) == 0:
    return ManagedIoResult[string](status: FileError.InvalidPath)
  var name = if kind == ManagedFileKind.Snapshot: "snapshot-" else: "journal-"
  for index in 0..<16:
    let nibble = int((uint64(epoch) shr ((15-index)*4)) and 15)
    name.add("0123456789abcdef"[nibble]) # Fixed full-width names cannot traverse outside the directory.
  if kind == ManagedFileKind.Snapshot: name.add(".bin")
  else: name.add(".wal")
  ManagedIoResult[string](status: FileError.None, completed: name)
proc writeAll(fd: cint, bytes: openArray[byte]): bool =
  ## Bound each native write by the actual remaining borrowed extent.
  var offset = 0
  while offset < bytes.len:
    let count = posix.write(fd, cast[pointer](unsafeAddr bytes[offset]), bytes.len-offset)
    if count <= 0 or count > bytes.len-offset: return false
    offset += count
  true
proc readNative(fd: cint, buffer: pointer, count: csize_t): clong {.importc: "read", cdecl,
    header: "<unistd.h>".}
  ## Supported Linux/macOS SDKs return signed-long ssize_t; explicit headers preserve the native ABI.
proc readAll(fd: cint, limit: ByteLimit): ManagedIoResult[seq[byte]] =
  ## Detect one excess byte without trusting file-size metadata or allocating beyond the configured limit.
  let maximum = min(uint64(limit), uint64(high(int)))
  var bytes: seq[byte] = @[]
  var buffer = default(array[4096, byte])
  while true:
    let requested = int(min(maximum-uint64(bytes.len), 4095'u64))+1
    let count = readNative(fd, addr buffer[0], csize_t(requested))
    if count < 0:
      if posix.errno() == interrupted: continue # Interrupted reads transfer no bytes; retry the same bounded extent.
      return ManagedIoResult[seq[byte]](status: FileError.IoFailure)
    if count == 0: break # Regular-file EOF alone authorizes a complete detached result.
    if uint64(count) > maximum-uint64(bytes.len):
      return ManagedIoResult[seq[byte]](status: FileError.LimitExceeded)
    for index in 0..<count: bytes.add(buffer[index])
  ManagedIoResult[seq[byte]](status: FileError.None, completed: bytes)
proc regular(fd: cint): bool =
  ## Refuse FIFOs/directories/devices even when nonblocking open itself succeeds.
  var metadata = default(Stat)
  posix.fstat(fd, metadata) == 0 and S_ISREG(metadata.st_mode)
proc parent(path: string): string =
  ## Select the original parent for anchoring exclusive directory creation.
  var slash = -1
  for index, character in path:
    if character == '/': slash = index
  if slash < 0: return "."
  if slash == 0: return "/"
  path[0..<slash]
proc acquire(directory: var ManagedDirectory, path: string, create: bool): FileError =
  ## Adopt no native resources until shape, lock and creation namespace barriers all succeed.
  if directory.opened: return FileError.Busy
  if path.len == 0 or path.len > high(int)-16: return FileError.InvalidPath
  for character in path:
    if character == char(0): return FileError.InvalidPath # C truncation must not change directory selection.
  var stop = path.len
  while stop > 1 and path[stop-1] == '/': dec stop
  var nativePath = path[0..<stop]
  if create and makeDirectory(nativePath.toCString(), 0o700) != 0:
    if posix.errno() == exists: return FileError.AlreadyExists
    return FileError.IoFailure
  var descriptor = openFile(nativePath.toCString(), O_RDONLY or O_CLOEXEC or directoryFlag or
      noFollow, 0)
  if descriptor < 0: return FileError.IoFailure
  var lockDescriptor = -1.cint
  var locked = false
  defer:
    if lockDescriptor >= 0:
      if locked: discard lockFile(lockDescriptor, unlock) # Every refused acquisition releases only its own lock.
      discard posix.close(lockDescriptor)
    if descriptor >= 0: discard posix.close(descriptor)
  var lockName = "LOCK"
  let flags = O_RDWR or O_CLOEXEC or O_NONBLOCK or noFollow
  lockDescriptor = openAt(descriptor, lockName.toCString(), flags or (if create: O_CREAT or
      O_EXCL else: 0), 0o600)
  if lockDescriptor < 0 or not regular(lockDescriptor): return FileError.IoFailure
  if lockFile(lockDescriptor, exclusive or nonblocking) != 0:
    let reason = posix.errno()
    if reason == wouldBlock or reason == again: return FileError.Busy
    return FileError.IoFailure
  locked = true
  if syncFile(lockDescriptor) != 0 or syncFile(descriptor) != 0: return FileError.IoFailure
  if create:
    var parentPath = parent(nativePath)
    let parentDescriptor = openFile(parentPath.toCString(), O_RDONLY or O_CLOEXEC or directoryFlag, 0)
    if parentDescriptor < 0: return FileError.IoFailure
    let synced = syncFile(parentDescriptor)
    let retired = posix.close(parentDescriptor)
    if synced != 0 or retired != 0: return FileError.IoFailure
  directory.data = DirectoryState(descriptor: descriptor, lockDescriptor: lockDescriptor,
      active: true, journals: 0)
  descriptor = -1
  lockDescriptor = -1
  FileError.None
proc initializeManagedDirectory*(directory: var ManagedDirectory, path: string): FileError =
  ## Exclusively create a missing directory and stable LOCK; failed bootstrap leaves forensic files.
  acquire(directory, path, true)
proc openManagedDirectory*(directory: var ManagedDirectory, path: string): FileError =
  ## Existing directories require their original regular LOCK file; no creation/fallback occurs.
  acquire(directory, path, false)
proc close*(directory: var ManagedDirectory): FileError =
  ## Refuse lock retirement while any journal still owns a live lease.
  let state = directory.data
  if state == nil or not state.active: return FileError.Uninitialized
  if state.journals != 0: return FileError.Busy
  let descriptor = state.descriptor
  let lockDescriptor = state.lockDescriptor
  state.active = false
  state.descriptor = -1
  state.lockDescriptor = -1
  directory.data = nil
  let released = lockFile(lockDescriptor, unlock)
  let lockRetired = posix.close(lockDescriptor)
  let retired = posix.close(descriptor)
  if released != 0 or lockRetired != 0 or retired != 0: return FileError.IoFailure
  FileError.None
proc synchronize*(directory: ManagedDirectory): FileError =
  ## Confirm all already published entries under the stable held namespace.
  if not directory.opened: return FileError.Uninitialized
  if syncFile(directory.nativeDescriptor) != 0: return FileError.IoFailure
  FileError.None
proc readManagedFile*(directory: ManagedDirectory, kind: ManagedFileKind, epoch: ManagedEpoch,
    limit: ByteLimit): ManagedIoResult[seq[byte]] =
  ## Read only a canonical regular child relative to the held directory and refuse symlink aliases.
  if not directory.opened: return ManagedIoResult[seq[byte]](status: FileError.Uninitialized)
  let named = managedFileName(kind, epoch)
  if named.error != FileError.None: return ManagedIoResult[seq[byte]](status: named.error)
  var name = named.value
  var descriptor = openAt(directory.nativeDescriptor, name.toCString(), O_RDONLY or O_CLOEXEC or
      O_NONBLOCK or noFollow, 0)
  if descriptor < 0: return ManagedIoResult[seq[byte]](status: FileError.IoFailure)
  defer:
    if descriptor >= 0: discard posix.close(descriptor) # Refused reads never leak their exact native descriptor.
  if not regular(descriptor): return ManagedIoResult[seq[byte]](status: FileError.IoFailure)
  let loaded = readAll(descriptor, limit)
  let closing = descriptor
  descriptor = -1
  if posix.close(closing) != 0: return ManagedIoResult[seq[byte]](status: FileError.IoFailure)
  loaded
proc createManagedFile*(directory: ManagedDirectory, kind: ManagedFileKind, epoch: ManagedEpoch,
    bytes: openArray[byte], limit: ByteLimit): FileError =
  ## Stage one exclusive immutable snapshot or journal prefix, syncing data before its directory entry.
  if not directory.opened: return FileError.Uninitialized
  if kind == ManagedFileKind.Current: return FileError.InvalidPath
  if uint64(bytes.len) > uint64(limit): return FileError.LimitExceeded
  let named = managedFileName(kind, epoch)
  if named.error != FileError.None: return named.error
  var name = named.value
  let flags = O_WRONLY or O_CREAT or O_EXCL or O_CLOEXEC or noFollow
  var descriptor = openAt(directory.nativeDescriptor, name.toCString(), flags, 0o600)
  if descriptor < 0:
    if posix.errno() == exists: return FileError.AlreadyExists
    return FileError.IoFailure
  defer:
    if descriptor >= 0: discard posix.close(descriptor) # Failed staged bytes remain unselected forensic files.
  if not writeAll(descriptor, bytes) or syncFile(descriptor) != 0: return FileError.IoFailure
  let closing = descriptor
  descriptor = -1
  if posix.close(closing) != 0: return FileError.IoFailure
  directory.synchronize
proc removeManagedFile*(directory: ManagedDirectory, kind: ManagedFileKind,
    epoch: ManagedEpoch): FileError =
  ## Remove only an explicitly unselected epoch child; CURRENT and LOCK are never reclamation targets.
  if not directory.opened: return FileError.Uninitialized
  if kind == ManagedFileKind.Current: return FileError.InvalidPath
  let named = managedFileName(kind, epoch)
  if named.error != FileError.None: return named.error
  var name = named.value
  let descriptor = openAt(directory.nativeDescriptor, name.toCString(), O_RDONLY or O_CLOEXEC or
      O_NONBLOCK or noFollow, 0)
  if descriptor < 0:
    if posix.errno() == missing: return FileError.None # Retrying removal of an already absent unselected file is harmless.
    return FileError.IoFailure
  let valid = regular(descriptor)
  let retired = posix.close(descriptor)
  if not valid or retired != 0: return FileError.IoFailure
  if unlinkAt(directory.nativeDescriptor, name.toCString(), 0) != 0: return FileError.IoFailure
  directory.synchronize

proc `=copy`*(destination: var ManagedJournal, source: ManagedJournal) {.error.}
  ## One native append descriptor has exactly one retirement owner.
proc `=dup`*(source: ManagedJournal): ManagedJournal {.error.}
  ## Lowering must reject hidden duplication of a live directory lease.
proc requireClosed(journal: ManagedJournal) {.requires: not journal.active.} =
  ## Explicit close releases the directory lease before its parent lock may retire.
  discard
proc `=destroy`*(journal: ManagedJournal) =
  ## A managed append descriptor may not outlive its observable close protocol.
  requireClosed(journal)
  `=destroy`(journal.state)
proc renameAt(sourceDirectory: cint, source: cstring, targetDirectory: cint,
    target: cstring): cint {.importc: "renameat", cdecl, header: "<stdio.h>".}
  ## Atomic CURRENT replacement stays within the exact held namespace.
proc truncateFile(fd: cint, extent: int64): cint {.importc: "ftruncate", cdecl,
    header: "<unistd.h>".}
  ## Only a separately trusted complete-prefix boundary may request truncation.
func opened*(journal: ManagedJournal): bool =
  ## Inspect descriptor lifetime independently from a potentially poisoned append result.
  journal.active
proc close*(journal: var ManagedJournal): FileError =
  ## Disarm one descriptor and release exactly one stable directory lease without retrying close.
  if not journal.active: return FileError.Uninitialized
  let state = journal.state
  assert state != nil and state.active and state.journals > 0
  let descriptor = journal.descriptor
  journal.active = false
  journal.descriptor = -1
  journal.state = nil
  dec state.journals
  if posix.close(descriptor) != 0: return FileError.IoFailure
  FileError.None
proc openManagedJournal*(journal: var ManagedJournal, directory: ManagedDirectory,
    epoch: ManagedEpoch, limit: ByteLimit): ManagedIoResult[seq[byte]] =
  ## Read the exact append inode once, then retain its directory lock lease after anchoring existing bytes.
  if journal.active: return ManagedIoResult[seq[byte]](status: FileError.Busy)
  let state = directory.data
  if state == nil or not state.active: return ManagedIoResult[seq[byte]](
      status: FileError.Uninitialized)
  if state.journals == high(int): return ManagedIoResult[seq[byte]](status: FileError.LimitExceeded)
  let named = managedFileName(ManagedFileKind.Journal, epoch)
  if named.error != FileError.None: return ManagedIoResult[seq[byte]](status: named.error)
  var name = named.value
  let flags = O_RDWR or O_APPEND or O_CLOEXEC or O_NONBLOCK or noFollow
  var descriptor = openAt(state.descriptor, name.toCString(), flags, 0)
  if descriptor < 0: return ManagedIoResult[seq[byte]](status: FileError.IoFailure)
  defer:
    if descriptor >= 0: discard posix.close(descriptor)
  if not regular(descriptor): return ManagedIoResult[seq[byte]](status: FileError.IoFailure)
  let loaded = readAll(descriptor, limit)
  if loaded.error != FileError.None: return loaded
  if syncFile(descriptor) != 0 or syncFile(state.descriptor) != 0:
    return ManagedIoResult[seq[byte]](status: FileError.IoFailure)
  journal.descriptor = descriptor
  journal.state = state
  journal.size = uint64(loaded.value.len)
  journal.limit = limit
  journal.poisoned = false
  journal.active = true
  inc state.journals
  descriptor = -1
  loaded
proc moveManagedJournal*(destination: var ManagedJournal, source: var ManagedJournal): FileError =
  ## Transfer an existing lease/descriptor into a closed slot without duplicating or retiring it.
  if destination.active: return FileError.Busy
  if not source.active: return FileError.Uninitialized
  destination.descriptor = source.descriptor
  destination.state = source.state
  destination.size = source.size
  destination.limit = source.limit
  destination.poisoned = source.poisoned
  destination.active = true
  source.active = false
  source.descriptor = -1
  source.state = nil
  FileError.None
proc managedJournalBytes*(journal: ManagedJournal): ManagedIoResult[uint64] =
  ## Fresh observations refuse after any uncertain append until a new owner reopens the bytes.
  if not journal.active: return ManagedIoResult[uint64](status: FileError.Uninitialized)
  if journal.poisoned: return ManagedIoResult[uint64](status: FileError.RecoveryRequired)
  ManagedIoResult[uint64](status: FileError.None, completed: journal.size)
proc appendManagedJournal*(journal: var ManagedJournal, bytes: openArray[byte]): FileError =
  ## Append only after remaining-capacity checks, then synchronize before reporting durability.
  if not journal.active: return FileError.Uninitialized
  if journal.poisoned: return FileError.RecoveryRequired
  if uint64(bytes.len) > min(uint64(journal.limit), uint64(high(int)))-journal.size:
    return FileError.LimitExceeded
  if not writeAll(journal.descriptor, bytes):
    journal.poisoned = true
    return FileError.IoFailure
  journal.size += uint64(bytes.len) # The exact remaining-byte preflight proved the addition.
  if syncFile(journal.descriptor) != 0:
    journal.poisoned = true
    return FileError.PublishedUnsynced
  FileError.None
proc truncateManagedJournal*(journal: var ManagedJournal, extent: uint64): FileError =
  ## Low-level explicit repair requires caller-verified prefix authority; it never chooses a rollback point.
  if not journal.active: return FileError.Uninitialized
  if journal.poisoned: return FileError.RecoveryRequired
  if extent < uint64(ManagedJournalHeaderBytes) or extent > journal.size or extent > uint64(high(int64)):
    return FileError.InvalidJournal
  if syncFile(journal.descriptor) != 0 or truncateFile(journal.descriptor, int64(extent)) != 0:
    journal.poisoned = true
    return FileError.IoFailure
  journal.size = extent
  if syncFile(journal.descriptor) != 0:
    journal.poisoned = true
    return FileError.PublishedUnsynced
  FileError.None
proc discardManagedPending*(directory: ManagedDirectory): FileError =
  ## The caller must first validate CURRENT before discarding its never-selected fixed staging file.
  if not directory.opened: return FileError.Uninitialized
  var name = "CURRENT.next"
  let descriptor = openAt(directory.nativeDescriptor, name.toCString(), O_RDONLY or O_CLOEXEC or
      O_NONBLOCK or noFollow, 0)
  if descriptor < 0:
    if posix.errno() == missing: return FileError.None
    return FileError.IoFailure
  let valid = regular(descriptor)
  let retired = posix.close(descriptor)
  if not valid or retired != 0: return FileError.IoFailure
  if unlinkAt(directory.nativeDescriptor, name.toCString(), 0) != 0: return FileError.IoFailure
  directory.synchronize
proc replaceManagedManifest*(directory: ManagedDirectory, bytes: openArray[byte],
    limit: ByteLimit): FileError =
  ## Stage/sync a complete candidate, atomically replace CURRENT, then synchronize the held directory.
  if not directory.opened: return FileError.Uninitialized
  if uint64(bytes.len) > uint64(limit): return FileError.LimitExceeded
  var pending = "CURRENT.next"
  let flags = O_WRONLY or O_CREAT or O_EXCL or O_CLOEXEC or noFollow
  var descriptor = openAt(directory.nativeDescriptor, pending.toCString(), flags, 0o600)
  if descriptor < 0:
    if posix.errno() == exists: return FileError.AlreadyExists
    return FileError.IoFailure
  defer:
    if descriptor >= 0: discard posix.close(descriptor) # Incomplete staged bytes remain unselected until explicit cleanup.
  if not writeAll(descriptor, bytes) or syncFile(descriptor) != 0: return FileError.IoFailure
  let closing = descriptor
  descriptor = -1
  if posix.close(closing) != 0: return FileError.IoFailure
  var current = "CURRENT"
  if renameAt(directory.nativeDescriptor, pending.toCString(), directory.nativeDescriptor,
      current.toCString()) != 0:
    return FileError.IoFailure
  if directory.synchronize != FileError.None: return FileError.PublishedUnsynced
  FileError.None
