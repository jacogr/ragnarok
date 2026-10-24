# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Directory-relative bounded paged IO with separate writer leases and immutable-epoch flock pins.
## Resources are explicit-close/move-only. Independent epoch directory descriptors survive writer retirement.
import std/assertions
import std/posix/posix
import ./[paged_codec, paged_stream, managed_manifest, file_errors, database_identity,
    full_paged_codec, full_paged_stream, full_paged_build]
import ../codec/[bounded, state_layout, state_trie]

type
  PagedIoResult*[T] = object ## Failed/default native outcomes carry no bytes or directory authority.
    case status: FileError
    of None: completed: T
    else: discard
  PagedPin* {.pure.} = enum ## Reclamation never upgrades a reader pin; each owner opens an independent descriptor.
    Shared, Exclusive, Create
  DirectoryData = ref object ## Stable private lease identity is never duplicated by copying an exported owner.
    fd, lease: cint
    active, writer: bool
    identity, lockIdentity: Stat
  PagedDirectory* = object ## Unique directory/optional writer-lease retirement authority.
    data: nil DirectoryData
  FileData = ref object ## Synchronous callbacks retain stable private state only for the duration of one algorithm call.
    fd, directory: cint
    active, poisoned, sealed, exclusive, anonymous: bool
    name: string
    identity, namespace: Stat
    size: uint64
    limit: ByteLimit
  PagedFile* = object ## Unique epoch/staging/replay descriptor and independent directory handle; named resources retain immutable native pins.
    data: nil FileData
  PagedFileIdentity* = object ## Passive exact inode/namespace receipt cannot create a file owner or pin.
    ready: bool
    file, directory: Stat
    size: uint64

func opened*(directory: PagedDirectory): bool =
  ## Default/moved/retired directory owners report no native authority.
  let data = directory.data
  data != nil and data.active
func opened*(file: PagedFile): bool =
  ## File state remains stable across moves while its exported close authority stays unique.
  let data = file.data
  data != nil and data.active
proc `=copy`*(destination: var PagedDirectory, source: PagedDirectory) {.error.}
  ## Writer leases and directory retirement have one owner.
proc `=dup`*(source: PagedDirectory): PagedDirectory {.error.}
  ## Actual lowering must reject hidden composite duplication.
proc `=copy`*(destination: var PagedFile, source: PagedFile) {.error.}
  ## Independent readers require independent opens, never descriptor-owner copies.
proc `=dup`*(source: PagedFile): PagedFile {.error.}
  ## No copied owner can close or unlock another resource's descriptor.
proc requireClosed(directory: PagedDirectory) {.requires: not directory.opened.} =
  ## Close failures remain observable instead of being hidden by destruction.
  discard
proc requireClosed(file: PagedFile) {.requires: not file.opened.} =
  ## Retiring the same reused descriptor number twice is forbidden.
  discard
proc `=destroy`*(directory: PagedDirectory) =
  ## Moved/default values pass; live native leases require explicit close.
  requireClosed(directory)
  `=destroy`(directory.data)
proc `=destroy`*(file: PagedFile) =
  ## The caller must retire a live file even after integrity/IO poison.
  requireClosed(file)
  `=destroy`(file.data)

let noFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
let directoryFlag {.importc: "O_DIRECTORY", header: "<fcntl.h>".}: cint
let shared {.importc: "LOCK_SH", header: "<sys/file.h>".}: cint
let exclusive {.importc: "LOCK_EX", header: "<sys/file.h>".}: cint
let nonblocking {.importc: "LOCK_NB", header: "<sys/file.h>".}: cint
let unlock {.importc: "LOCK_UN", header: "<sys/file.h>".}: cint
let interrupted {.importc: "EINTR", header: "<errno.h>".}: cint
let wouldBlock {.importc: "EWOULDBLOCK", header: "<errno.h>".}: cint
let again {.importc: "EAGAIN", header: "<errno.h>".}: cint
let exists {.importc: "EEXIST", header: "<errno.h>".}: cint
let missing {.importc: "ENOENT", header: "<errno.h>".}: cint
let noFollowStat {.importc: "AT_SYMLINK_NOFOLLOW", header: "<fcntl.h>".}: cint
proc openNative(path: cstring, flags, mode: cint): cint {.importc: "open", cdecl,
    header: "<fcntl.h>".}
  ## Real SDK declarations retain native flags and variadic mode promotion.
proc openAt(fd: cint, path: cstring, flags, mode: cint): cint {.importc: "openat", cdecl,
    header: "<fcntl.h>".}
  ## Every child is a fixed name resolved under the held directory.
proc closeNative(fd: cint): cint {.importc: "close", cdecl, header: "<unistd.h>".}
  ## Never retry native close, even when EINTR makes retirement uncertain.
proc mkdirNative(path: cstring, mode: cint): cint {.importc: "mkdir", cdecl,
    header: "<sys/stat.h>".}
  ## A new namespace is exclusive and private; failed bootstrap preserves forensic files.
proc statAt(fd: cint, path: cstring, metadata: var Stat, flags: cint): cint {.importc: "fstatat",
    cdecl, header: "<sys/stat.h>".}
  ## Inspect the named inode without following a substituted symbolic link.
proc lockNative(fd, operation: cint): cint {.importc: "flock", cdecl, header: "<sys/file.h>".}
  ## Pins use supported Linux/macOS open-file-description flock behavior.
proc syncNative(fd: cint): cint {.importc: "fsync", cdecl, header: "<unistd.h>".}
  ## File bytes and directory selection have distinct durability barriers.
proc readNative(fd: cint, output: pointer, length: csize_t): clong {.importc: "read", cdecl,
    header: "<unistd.h>".}
  ## Exact bounded windows use real SDK signed ssize_t results.
proc writeNative(fd: cint, input: pointer, length: csize_t): clong {.importc: "write", cdecl,
    header: "<unistd.h>".}
  ## Positive short progress advances only the actual transferred prefix.
proc seekNative(fd: cint, offset: int64, origin: cint): int64 {.importc: "lseek", cdecl,
    header: "<unistd.h>".}
  ## Each resource is synchronous and owns an independent descriptor; no shared seek cursor escapes.
proc renameAt(a: cint, source: cstring, b: cint, target: cstring): cint {.importc: "renameat",
    cdecl, header: "<stdio.h>".}
  ## Atomic namespace selection is relative to one held directory.
proc unlinkAt(fd: cint, path: cstring, flags: cint): cint {.importc: "unlinkat", cdecl,
    header: "<unistd.h>".}
  ## Only a captured canonical epoch with an exclusive pin may be removed.
type CStream {.importc: "FILE", header: "<stdio.h>".} = object ## SDK-owned opaque anonymous temporary stream.
let getFlags {.importc: "F_GETFL", header: "<fcntl.h>".}: cint
let setFlags {.importc: "F_SETFL", header: "<fcntl.h>".}: cint
let duplicateCloseExec {.importc: "F_DUPFD_CLOEXEC", header: "<fcntl.h>".}: cint
proc temporaryNative(): ptr CStream {.importc: "tmpfile", cdecl, header: "<stdio.h>".}
  ## libc creates and unlinks scratch transport before the descriptor escapes.
proc descriptorNative(stream: ptr CStream): cint {.importc: "fileno", cdecl, header: "<stdio.h>".}
  ## Borrow the stream's descriptor only long enough to create an independent close authority.
proc retireStream(stream: ptr CStream): cint {.importc: "fclose", cdecl, header: "<stdio.h>".}
  ## Retire the bootstrap FILE exactly once; subsequent IO uses only the separately owned descriptor.
proc duplicateNative(fd, operation, minimum: cint): cint {.importc: "fcntl", cdecl,
    header: "<fcntl.h>".}
  ## The SDK variadic command duplicates with atomic close-on-exec on supported Linux/macOS.
func error*[T](outcome: PagedIoResult[T]): FileError =
  ## Observe typed native failures without extracting an inactive payload.
  outcome.status
func value*[T](outcome: PagedIoResult[T]): T {.inline, requires: outcome.status ==
    FileError.None.} =
  ## Only complete bounded IO grants detached bytes or passive identity metadata.
  outcome.completed
proc lock(fd, operation: cint): cint =
  ## EINTR repeats the same lock operation; nonblocking Busy never spins.
  while true:
    let status = lockNative(fd, operation)
    if status == 0 or posix.errno() != interrupted: return status
proc sync(fd: cint): cint =
  ## Interrupted barriers are not durability receipts; permanent failure remains uncertainty.
  while true:
    let status = syncNative(fd)
    if status == 0 or posix.errno() != interrupted: return status
func same(a, b: Stat): bool =
  ## Native inode identity includes device; byte equality alone cannot revive a stale owner.
  a.st_dev == b.st_dev and a.st_ino == b.st_ino
func sameVersion(a, b: Stat): bool =
  ## Nanosecond modification time strengthens a captured inode against equal-size rewrite/reuse.
  same(a, b) and clong(a.st_mtim.tv_sec) == clong(b.st_mtim.tv_sec) and a.st_mtim.tv_nsec ==
      b.st_mtim.tv_nsec
proc named(fd: cint, name: string, metadata: var Stat): bool =
  ## Every internal name is fixed/canonical; synchronous C-string storage outlives the syscall.
  var path = name
  statAt(fd, path.toCString(), metadata, noFollowStat) == 0
proc identity(data: FileData): bool =
  ## Require the original regular named inode, independent held directory and exact tracked extent.
  var held = default(Stat)
  var path = default(Stat)
  var directory = default(Stat)
  if posix.fstat(data.fd, held) != 0 or not S_ISREG(held.st_mode) or held.st_size < 0: return false
  if posix.fstat(data.directory, directory) != 0 or not same(directory,
      data.namespace): return false
  if not same(held, data.identity) or uint64(held.st_size) != data.size: return false
  if data.sealed and not sameVersion(held, data.identity): return false
  if data.anonymous: return true
  named(data.directory, data.name, path) and S_ISREG(path.st_mode) and same(path, data.identity) and
      path.st_size == held.st_size
proc check*(file: PagedFile): FileError =
  ## Integrity uncertainty latches on the stable private resource until explicit close.
  let data = file.data
  if data == nil or not data.active: return FileError.Uninitialized
  if data.poisoned: return FileError.RecoveryRequired
  if not identity(data):
    data.poisoned = true
    return FileError.RecoveryMismatch
  FileError.None
proc check*(directory: PagedDirectory): FileError =
  ## A replaced LOCK inode cannot let two writers operate under different lease names.
  let data = directory.data
  if data == nil or not data.active: return FileError.Uninitialized
  var held = default(Stat)
  if posix.fstat(data.fd, held) != 0 or not same(held,
      data.identity): return FileError.RecoveryMismatch
  if data.lease >= 0:
    var lock = default(Stat)
    if not named(data.fd, "LOCK", lock) or not S_ISREG(lock.st_mode) or not same(lock,
        data.lockIdentity):
      return FileError.RecoveryMismatch
  FileError.None
proc close*(file: var PagedFile): FileError =
  ## Mark retirement before each native close; reuse of its integer descriptor can never trigger a retry.
  let data = file.data
  if data == nil or not data.active: return FileError.Uninitialized
  data.active = false
  let fd = data.fd
  let directory = data.directory
  data.fd = -1
  data.directory = -1
  file.data = nil
  let retired = closeNative(fd)
  let parentRetired = closeNative(directory)
  if retired != 0 or parentRetired != 0: return FileError.IoFailure
  FileError.None
proc close*(directory: var PagedDirectory): FileError =
  ## Independent epoch handles retain no lease, so readers/candidates do not prevent writer close.
  let data = directory.data
  if data == nil or not data.active: return FileError.Uninitialized
  data.active = false
  let fd = data.fd
  let lease = data.lease
  data.fd = -1
  data.lease = -1
  directory.data = nil
  var failed = false
  if lease >= 0:
    if data.writer and lock(lease, unlock) != 0: failed = true
    if closeNative(lease) != 0: failed = true
  if closeNative(fd) != 0: failed = true
  if failed: FileError.IoFailure else: FileError.None
proc epochName*(epoch: ManagedEpoch): PagedIoResult[string] =
  ## Fixed full-width lowercase hexadecimal names have no caller-controlled path fragments.
  if uint64(epoch) == 0: return PagedIoResult[string](status: FileError.InvalidPath)
  var name = "paged-"
  for index in 0..<16: name.add("0123456789abcdef"[int((uint64(epoch) shr ((15-index)*4)) and 15)])
  name.add(".bin")
  PagedIoResult[string](status: FileError.None, completed: name)
proc openDirectory*(directory: var PagedDirectory, path: string, create, writer: bool): FileError =
  ## Readers never acquire LOCK; writer opens require the persistent exact regular LOCK inode.
  if directory.opened: return FileError.Busy
  when not (defined(linux) or defined(macosx)):
    return FileError.UnsupportedLayout
  if path.len == 0: return FileError.InvalidPath
  for c in path:
    if c == char(0): return FileError.InvalidPath
  var stop = path.len
  while stop > 1 and path[stop-1] == '/': dec stop
  var nativePath = path[0..<stop]
  if create and not writer: return FileError.InvalidPath
  if create and mkdirNative(nativePath.toCString(), 0o700) != 0:
    if posix.errno() == exists: return FileError.AlreadyExists
    return FileError.IoFailure
  var fd = openNative(nativePath.toCString(), O_RDONLY or O_CLOEXEC or directoryFlag or noFollow, 0)
  if fd < 0: return FileError.IoFailure
  var lease = -1.cint
  defer:
    if lease >= 0 and closeNative(lease) != 0: result = FileError.IoFailure
    if fd >= 0 and closeNative(fd) != 0: result = FileError.IoFailure
  var metadata = default(Stat)
  if posix.fstat(fd, metadata) != 0 or not S_ISDIR(metadata.st_mode): return FileError.IoFailure
  var lockMetadata = default(Stat)
  var lockName = "LOCK"
  lease = openAt(fd, lockName.toCString(), (if writer: O_RDWR else: O_RDONLY) or O_NONBLOCK or
    O_CLOEXEC or noFollow or (if create: O_CREAT or O_EXCL else: 0), 0o600)
  if lease < 0 or posix.fstat(lease, lockMetadata) != 0 or not S_ISREG(
      lockMetadata.st_mode): return FileError.IoFailure
  if writer:
    if lock(lease, exclusive or nonblocking) != 0:
      if posix.errno() == wouldBlock or posix.errno() == again: return FileError.Busy
      return FileError.IoFailure
    if sync(lease) != 0 or sync(fd) != 0: return FileError.IoFailure
  if create:
    var slash = -1
    for index, c in nativePath:
      if c == '/': slash = index
    var parent = if slash < 0: "." elif slash == 0: "/" else: nativePath[0..<slash]
    let parentFd = openNative(parent.toCString(), O_RDONLY or O_CLOEXEC or directoryFlag, 0)
    if parentFd < 0: return FileError.IoFailure
    let synced = sync(parentFd)
    let retired = closeNative(parentFd)
    if synced != 0 or retired != 0: return FileError.IoFailure
  directory.data = DirectoryData(fd: fd, lease: lease, active: true, writer: writer,
    identity: metadata, lockIdentity: lockMetadata)
  fd = -1
  lease = -1
  directory.check
proc openNamed(file: var PagedFile, directory: PagedDirectory, child: string,
    pin: PagedPin, limit: ByteLimit): FileError =
  ## Create/pin exactly one no-follow regular file; every file owns an independent held-directory descriptor.
  if file.opened: return FileError.Busy
  let checked = directory.check
  if checked != FileError.None: return checked
  let data = directory.data
  assert data != nil
  if pin != PagedPin.Shared and not data.writer: return FileError.WrongIdentity
  var name = child
  let flags = O_CLOEXEC or O_NONBLOCK or noFollow or
    (if pin == PagedPin.Create: O_RDWR or O_CREAT or O_EXCL or O_APPEND else: O_RDONLY)
  var fd = openAt(data.fd, name.toCString(), flags, 0o600)
  if fd < 0:
    if posix.errno() == exists: return FileError.AlreadyExists
    return FileError.IoFailure
  var parent = -1.cint
  defer:
    if fd >= 0 and closeNative(fd) != 0: result = FileError.IoFailure
    if parent >= 0 and closeNative(parent) != 0: result = FileError.IoFailure
  if lock(fd, (if pin == PagedPin.Shared: shared else: exclusive) or nonblocking) != 0:
    if posix.errno() == wouldBlock or posix.errno() == again: return FileError.Busy
    return FileError.IoFailure
  var metadata = default(Stat)
  if posix.fstat(fd, metadata) != 0 or not S_ISREG(metadata.st_mode) or metadata.st_size <
      0: return FileError.IoFailure
  if uint64(metadata.st_size) > uint64(limit): return FileError.LimitExceeded
  if pin == PagedPin.Create and metadata.st_size != 0: return FileError.RecoveryMismatch
  var dot = "."
  parent = openAt(data.fd, dot.toCString(), O_RDONLY or O_CLOEXEC or directoryFlag or noFollow, 0)
  if parent < 0: return FileError.IoFailure
  file.data = FileData(fd: fd, directory: parent, active: true, name: name, identity: metadata,
    namespace: data.identity, size: uint64(metadata.st_size), limit: limit,
    exclusive: pin != PagedPin.Shared, sealed: pin != PagedPin.Create)
  fd = -1
  parent = -1
  file.check
proc openEpoch*(file: var PagedFile, directory: PagedDirectory, epoch: ManagedEpoch,
    pin: PagedPin, limit: ByteLimit): FileError =
  ## Epoch owners accept only one canonical counter-derived name.
  let name = epochName(epoch)
  if name.error != FileError.None: return name.error
  openNamed(file, directory, name.value, pin, limit)
proc openTemporary(file: var PagedFile, directory: PagedDirectory, limit: ByteLimit,
    appendOnly, writerRequired: bool): FileError =
  ## Anonymous replay transport uses a uniquely owned CLOEXEC descriptor and never creates a database candidate name.
  if file.opened: return FileError.Busy
  let checked = directory.check
  if checked != FileError.None: return checked
  let owner = directory.data
  assert owner != nil
  if writerRequired and not owner.writer: return FileError.WrongIdentity
  let stream = temporaryNative()
  if stream == nil: return FileError.IoFailure
  let original = descriptorNative(stream)
  let fd = if original < 0: -1.cint else: duplicateNative(original, duplicateCloseExec, 0)
  let retired = retireStream(stream)
  if fd < 0: return FileError.IoFailure
  var handle = fd
  var parent = -1.cint
  defer:
    if handle >= 0 and closeNative(handle) != 0: result = FileError.IoFailure
    if parent >= 0 and closeNative(parent) != 0: result = FileError.IoFailure
  if retired != 0: return FileError.IoFailure
  let flags = duplicateNative(fd, getFlags, 0)
  if flags < 0: return FileError.IoFailure
  if appendOnly and duplicateNative(fd, setFlags, flags or O_APPEND) != 0:
    return FileError.IoFailure
  var metadata = default(Stat)
  if posix.fstat(fd, metadata) != 0 or not S_ISREG(metadata.st_mode) or metadata.st_size != 0:
    return FileError.IoFailure
  var dot = "."
  parent = openAt(owner.fd, dot.toCString(), O_RDONLY or O_CLOEXEC or directoryFlag or noFollow, 0)
  if parent < 0: return FileError.IoFailure
  file.data = FileData(fd: handle, directory: parent, active: true, anonymous: true,
    identity: metadata, namespace: owner.identity, size: 0, limit: limit, exclusive: true)
  handle = -1
  parent = -1
  file.check
proc openScratch*(file: var PagedFile, directory: PagedDirectory, limit: ByteLimit): FileError =
  ## Preserve the writer-only append replay transport; graph workspace uses a private separate mode.
  openTemporary(file, directory, limit, true, true)
proc openPendingWidth(file: var PagedFile, directory: PagedDirectory, width: int): PagedIoResult[bool] =
  ## Capture only the fixed optional staging file; no scan or unknown-prefix adoption is authorized.
  let checked = directory.check
  if checked != FileError.None: return PagedIoResult[bool](status: checked)
  let owner = directory.data
  assert owner != nil
  var metadata = default(Stat)
  if not named(owner.fd, "CURRENT.next", metadata):
    if posix.errno() == missing: return PagedIoResult[bool](status: FileError.None,
        completed: false)
    return PagedIoResult[bool](status: FileError.IoFailure)
  let acquired = openNamed(file, directory, "CURRENT.next", PagedPin.Exclusive, ByteLimit(width))
  if acquired != FileError.None: return PagedIoResult[bool](status: acquired)
  PagedIoResult[bool](status: FileError.None, completed: true)
proc openPending*(file: var PagedFile, directory: PagedDirectory): PagedIoResult[bool] =
  ## Preserve the light-format staging extent contract.
  openPendingWidth(file, directory, PagedManifestBytes)
proc openFullPending*(file: var PagedFile, directory: PagedDirectory): PagedIoResult[bool] =
  ## Full cleanup captures only a full-width-or-shorter staging prefix under an exclusive pin.
  openPendingWidth(file, directory, FullPagedManifestBytes)
proc readSelection(directory: PagedDirectory, width: int): PagedIoResult[seq[byte]] =
  ## CURRENT is bounded metadata, never a selected data-file fallback or whole-file image read.
  let checked = directory.check
  if checked != FileError.None: return PagedIoResult[seq[byte]](status: checked)
  let data = directory.data
  assert data != nil
  var name = "CURRENT"
  var fd = openAt(data.fd, name.toCString(), O_RDONLY or O_CLOEXEC or O_NONBLOCK or noFollow, 0)
  if fd < 0: return PagedIoResult[seq[byte]](status: FileError.IoFailure)
  defer:
    if fd >= 0 and closeNative(fd) != 0: result = PagedIoResult[seq[byte]](
        status: FileError.IoFailure)
  var metadata = default(Stat)
  if posix.fstat(fd, metadata) != 0 or not S_ISREG(metadata.st_mode) or metadata.st_size != width:
    return PagedIoResult[seq[byte]](status: FileError.UnsupportedLayout)
  var bytes = newSeq[byte](width)
  var filled = 0
  while filled < bytes.len:
    let count = readNative(fd, addr bytes[filled], csize_t(bytes.len-filled))
    if count < 0 and posix.errno() == interrupted: discard
    elif count <= 0 or count > bytes.len-filled: return PagedIoResult[seq[byte]](
        status: FileError.IoFailure)
    else: filled += int(count)
  var extra = 0'u8
  var count = -1.clong
  while count < 0:
    count = readNative(fd, addr extra, 1)
    if count < 0 and posix.errno() != interrupted: return PagedIoResult[seq[byte]](
        status: FileError.IoFailure)
  if count != 0: return PagedIoResult[seq[byte]](status: FileError.RecoveryMismatch)
  let retiring = fd
  fd = -1
  if closeNative(retiring) != 0: return PagedIoResult[seq[byte]](status: FileError.IoFailure)
  PagedIoResult[seq[byte]](status: FileError.None, completed: bytes)
proc readCurrent*(directory: PagedDirectory): PagedIoResult[seq[byte]] =
  ## Existing light CURRENT accepts only its exact versioned width.
  readSelection(directory, PagedManifestBytes)
proc readFullCurrent*(directory: PagedDirectory): PagedIoResult[seq[byte]] =
  ## Full CURRENT has a separate fixed width/schema and cannot silently reopen light V1.
  readSelection(directory, FullPagedManifestBytes)
proc writeAll(fd: cint, bytes: openArray[byte]): bool =
  ## Genuine short progress advances; EINTR transfers no bytes and never repeats completed bytes.
  var offset = 0
  while offset < bytes.len:
    let count = writeNative(fd, cast[pointer](unsafeAddr bytes[offset]), csize_t(bytes.len-offset))
    if count < 0 and posix.errno() == interrupted: discard
    elif count <= 0 or count > bytes.len-offset: return false
    else: offset += int(count)
  true
proc input(data: FileData): PagedInput =
  ## Private borrowed callbacks never escape a synchronous validate/build/lookup wrapper.
  proc read(offset: PagedOffset, output: var openArray[byte]): bool {.closure.} =
    ## Exact held-inode reads use one descriptor-local seek cursor; resource calls must be serialized by the caller.
    if not data.active or data.poisoned: return false
    let start = uint64(offset)
    if not identity(data) or start > data.size or uint64(output.len) > data.size-start:
      data.poisoned = true
      return false
    if seekNative(data.fd, int64(start), SEEK_SET) != int64(start):
      data.poisoned = true
      return false
    var filled = 0
    while filled < output.len:
      let count = readNative(data.fd, addr output[filled], csize_t(output.len-filled))
      if count < 0 and posix.errno() == interrupted: discard
      elif count <= 0 or count > output.len-filled:
        data.poisoned = true
        return false
      else: filled += int(count)
    true
  proc extent(output: var uint64): bool {.closure.} =
    ## Fstat/name identity and real EOF jointly reject replacement, growth and early truncation.
    if not data.active or data.poisoned or not identity(data):
      data.poisoned = true
      return false
    if seekNative(data.fd, int64(data.size), SEEK_SET) != int64(data.size):
      data.poisoned = true
      return false
    var extra = 0'u8
    var count = -1.clong
    while count < 0:
      count = readNative(data.fd, addr extra, 1)
      if count < 0 and posix.errno() != interrupted:
        data.poisoned = true
        return false
    if count != 0:
      data.poisoned = true
      return false
    output = data.size
    true
  PagedInput(read: read, extent: extent)
proc matchesPrefix*(file: var PagedFile, expected: var PagedFile,
    budget: PagedWorkLimits): FileError =
  ## Compare one captured partial candidate with the exact fully reproduced artifact, at most two pages at a time.
  let checked = file.check
  if checked != FileError.None: return checked
  let verified = expected.check
  if verified != FileError.None: return verified
  let actual = file.data
  let reference = expected.data
  assert actual != nil and reference != nil
  if actual.size > reference.size: return FileError.RecoveryMismatch
  let readLimit = uint64(budget.readBytes)
  let chunks = actual.size div uint64(PagedPageBytes)+(if actual.size mod uint64(PagedPageBytes) ==
      0: 0'u64 else: 1'u64)
  if readLimit < 2 or actual.size > (readLimit-2) div 2 or chunks*2+2 > uint64(
      budget.ioCalls): return FileError.LimitExceeded
  let source = input(actual)
  let replay = input(reference)
  assert source.read != nil and source.extent != nil and replay.read != nil and replay.extent != nil
  var left = default(array[PagedPageBytes, byte])
  var right = default(array[PagedPageBytes, byte])
  var offset = 0'u64
  while offset < actual.size:
    # Difference-before-addition bounds both exact reads and final partial page/digest fragments.
    let count = int(min(uint64(PagedPageBytes), actual.size-offset))
    if not source.read(PagedOffset(offset), left.toOpenArray(0,
        count-1)): return FileError.IoFailure
    if not replay.read(PagedOffset(offset), right.toOpenArray(0,
        count-1)): return FileError.IoFailure
    for index in 0..<count:
      if left[index] != right[index]: return FileError.RecoveryMismatch
    offset += uint64(count)
  var size = 0'u64
  if not source.extent(size) or size != actual.size: return FileError.RecoveryMismatch
  if not replay.extent(size) or size != reference.size: return FileError.RecoveryMismatch
  FileError.None
proc matchesManifestPrefix(file: var PagedFile, bytes: openArray[byte],
    budget: PagedWorkLimits, width: int): FileError =
  ## Fixed manifest prefixes are bounded before reading and retain no detached staging authority.
  let checked = file.check
  if checked != FileError.None: return checked
  let actual = file.data
  assert actual != nil
  if bytes.len != width or actual.size > uint64(
      bytes.len): return FileError.RecoveryMismatch
  let calls = if actual.size == 0: 1'u64 else: 2'u64
  if actual.size+1 > uint64(budget.readBytes) or calls > uint64(
      budget.ioCalls): return FileError.LimitExceeded
  var raw = default(array[PagedManifestBytes, byte])
  let source = input(actual)
  assert source.read != nil and source.extent != nil
  let count = int(actual.size)
  if count > 0:
    # Even a one-byte or checksum-fragment staging file must match the independently reconstructed manifest.
    if not source.read(PagedOffset(0), raw.toOpenArray(0, count-1)): return FileError.IoFailure
    for index in 0..<count:
      if raw[index] != bytes[index]: return FileError.RecoveryMismatch
  var size = 0'u64
  if not source.extent(size) or size != actual.size: return FileError.RecoveryMismatch
  FileError.None
proc matchesPrefix*(file: var PagedFile, bytes: openArray[byte],
    budget: PagedWorkLimits): FileError =
  ## Light callers retain exact193-byte reference requirements.
  matchesManifestPrefix(file, bytes, budget, PagedManifestBytes)
proc matchesFullPrefix*(file: var PagedFile, bytes: openArray[byte],
    budget: PagedWorkLimits): FileError =
  ## Full callers require exact192-byte independently replayed manifest evidence.
  matchesManifestPrefix(file, bytes, budget, FullPagedManifestBytes)
proc latch(data: FileData, reason: PagedStreamError) =
  ## Pure policy/provider refusals preserve usable owners; integrity/IO uncertainty requires strict reopen.
  case reason
  of PagedStreamError.None, PagedStreamError.UnknownKey, PagedStreamError.LimitExceeded,
      PagedStreamError.BackendFailure, PagedStreamError.UnsupportedPolicy:
    # Checked policy/provider refusals leave the native resource usable.
    discard
  else:
    # Corruption and uncertain IO cannot be used again without a strict fresh open.
    data.poisoned = true
proc validateFile*(file: var PagedFile, selected: PagedManifest,
    limits: PagedStreamLimits): PagedStreamResult[CheckedPagedArtifact] =
  ## The stream engine validates all bytes/proofs while this native pin remains held.
  let data = file.data
  if data == nil or not data.active: return validatePagedArtifact(default(PagedInput), selected, limits)
  let checked = validatePagedArtifact(input(data), selected, limits)
  latch(data, checked.error)
  checked
proc lookupFile*(file: var PagedFile, checked: CheckedPagedArtifact, query: StateKey,
    budget: PagedWorkLimits): PagedStreamResult[PagedLookup] =
  ## Owned verified lookups outlive file close; native uncertainty latches independently of immutable metadata.
  let data = file.data
  if data == nil or not data.active: return lookupPaged(checked, default(PagedInput), query, budget)
  let found = lookupPaged(checked, input(data), query, budget)
  latch(data, found.error)
  found
proc appender(data: FileData): PagedAppend =
  ## Capture a statically non-nil stable file state in a synchronous-only append callback.
  proc append(bytes: openArray[byte]): bool {.closure.} =
    ## O_APPEND preserves the sequential prefix even after the build's verification reads seek elsewhere.
    if not identity(data) or data.poisoned or data.sealed:
      data.poisoned = true
      return false
    let maximum = min(uint64(data.limit), uint64(high(int)))
    if data.size > maximum or uint64(bytes.len) > maximum-data.size: return false
    if not writeAll(data.fd, bytes):
      data.poisoned = true
      return false
    data.size += uint64(bytes.len)
    true
  append
proc sealed(data: FileData, built: PagedStreamResult[CheckedPagedArtifact]): PagedIoResult[
    PagedStreamResult[CheckedPagedArtifact]] =
  ## Seal only complete stream success and a successful fresh metadata capture.
  if built.error == PagedStreamError.None:
    var metadata = default(Stat)
    if posix.fstat(data.fd, metadata) != 0:
      data.poisoned = true
      return PagedIoResult[PagedStreamResult[CheckedPagedArtifact]](status: FileError.IoFailure)
    else:
      data.identity = metadata
      data.sealed = true
  PagedIoResult[PagedStreamResult[CheckedPagedArtifact]](status: FileError.None, completed: built)
proc buildFile*(file: var PagedFile, producer: nil PagedProducer, header: PagedHeader,
    limits: PagedStreamLimits): PagedIoResult[PagedStreamResult[CheckedPagedArtifact]] =
  ## Only a newly created exclusive empty owner can append; failures preserve unsealed forensic bytes.
  let data = file.data
  if data == nil or not data.active or data.sealed or data.poisoned:
    return PagedIoResult[PagedStreamResult[CheckedPagedArtifact]](
        status: FileError.RecoveryRequired)
  let built = buildPagedArtifact(PagedOutput(source: input(data), append: appender(data)), producer,
      header, limits)
  latch(data, built.error)
  sealed(data, built)
proc compactFile*(file: var PagedFile, source: var PagedFile, checked: CheckedPagedArtifact,
    target: PagedHeader): PagedIoResult[PagedStreamResult[CheckedPagedArtifact]] =
  ## Borrow independent exclusive destination and shared source pins only during the synchronous copy.
  let destination = file.data
  let original = source.data
  if destination == nil or original == nil: return PagedIoResult[PagedStreamResult[
      CheckedPagedArtifact]](status: FileError.Uninitialized)
  if not destination.active or destination.sealed or destination.poisoned or not original.active:
    return PagedIoResult[PagedStreamResult[CheckedPagedArtifact]](
        status: FileError.RecoveryRequired)
  let built = compactPagedArtifact(PagedOutput(source: input(destination), append: appender(
      destination)), input(original), checked, target)
  latch(destination, built.error)
  if built.error != PagedStreamError.None and not identity(original): original.poisoned = true
  sealed(destination, built)
proc synchronize*(file: PagedFile): FileError =
  ## Complete validation precedes the file barrier; metadata/name/extent remain bound to the held pin.
  let checked = file.check
  if checked != FileError.None: return checked
  let data = file.data
  assert data != nil
  if sync(data.fd) != 0:
    data.poisoned = true
    return FileError.IoFailure
  FileError.None
proc synchronize*(directory: PagedDirectory): FileError =
  ## Namespace barriers are explicit, including already-absent reclamation retries.
  let checked = directory.check
  if checked != FileError.None: return checked
  let data = directory.data
  assert data != nil
  if sync(data.fd) != 0: FileError.IoFailure else: FileError.None
proc fileIdentity*(file: PagedFile): PagedIoResult[PagedFileIdentity] =
  ## Capture only a currently checked inode/namespace/extent; receipts own no descriptor or pin.
  let checked = file.check
  if checked != FileError.None: return PagedIoResult[PagedFileIdentity](status: checked)
  let data = file.data
  assert data != nil
  PagedIoResult[PagedFileIdentity](status: FileError.None,
    completed: PagedFileIdentity(ready: true, file: data.identity, directory: data.namespace,
        size: data.size))
func matches*(receipt: PagedFileIdentity, actual: PagedFileIdentity): bool =
  ## Equal bytes or descriptor numbers cannot replace the captured inode identity.
  receipt.ready and actual.ready and sameVersion(receipt.file, actual.file) and same(
      receipt.directory, actual.directory) and receipt.size == actual.size
proc sameDirectory*(directory: PagedDirectory, file: PagedFile): bool =
  ## Passive receipts/candidates remain bound to the original held directory inode.
  let a = directory.data
  let b = file.data
  if a == nil or b == nil: return false
  a.active and b.active and same(a.identity, b.namespace)
proc pendingAbsent*(directory: PagedDirectory): FileError =
  ## Unknown staging files block publication/cleanup and remain untouched for explicit recovery.
  let checked = directory.check
  if checked != FileError.None: return checked
  let data = directory.data
  assert data != nil
  var metadata = default(Stat)
  if named(data.fd, "CURRENT.next", metadata): return FileError.AlreadyExists
  if posix.errno() != missing: return FileError.IoFailure
  FileError.None
proc replaceSelection(directory: PagedDirectory, bytes: openArray[byte], width: int,
    beforeRename: proc(): FileError {.closure.}): FileError =
  ## Stage/fsync/close/rename/fsync the exact bounded manifest; uncertain publication never grants a receipt.
  let checked = directory.pendingAbsent
  if checked != FileError.None: return checked
  let data = directory.data
  assert data != nil
  if not data.writer or bytes.len != width: return FileError.WrongIdentity
  var pending = "CURRENT.next"
  var fd = openAt(data.fd, pending.toCString(), O_RDWR or O_CREAT or O_EXCL or O_CLOEXEC or
      noFollow, 0o600)
  if fd < 0:
    if posix.errno() == exists: return FileError.AlreadyExists
    return FileError.IoFailure
  defer:
    if fd >= 0 and closeNative(fd) != 0: result = FileError.IoFailure
  if not writeAll(fd, bytes) or sync(fd) != 0: return FileError.IoFailure
  let retiring = fd
  fd = -1
  if closeNative(retiring) != 0: return FileError.IoFailure
  let verified = beforeRename()
  if verified != FileError.None: return verified
  var current = "CURRENT"
  if renameAt(data.fd, pending.toCString(), data.fd, current.toCString()) !=
      0: return FileError.IoFailure
  if sync(data.fd) != 0: return FileError.PublishedUnsynced
  FileError.None
proc replaceCurrent*(directory: PagedDirectory, bytes: openArray[byte],
    beforeRename: proc(): FileError {.closure.}): FileError =
  ## Existing light publication keeps its exact schema width and native ordering.
  replaceSelection(directory, bytes, PagedManifestBytes, beforeRename)
proc replaceFullCurrent*(directory: PagedDirectory, bytes: openArray[byte],
    beforeRename: proc(): FileError {.closure.}): FileError =
  ## Full publication uses the same guarded barriers with its distinct fixed-width selection.
  replaceSelection(directory, bytes, FullPagedManifestBytes, beforeRename)
proc epochExists*(directory: PagedDirectory, epoch: ManagedEpoch): PagedIoResult[bool] =
  ## Probe only one explicitly requested canonical epoch; absence never authorizes a directory sweep.
  let checked = directory.check
  if checked != FileError.None: return PagedIoResult[bool](status: checked)
  let data = directory.data
  assert data != nil
  let name = epochName(epoch)
  if name.error != FileError.None: return PagedIoResult[bool](status: name.error)
  var metadata = default(Stat)
  if named(data.fd, name.value, metadata): return PagedIoResult[bool](status: FileError.None,
      completed: true)
  if posix.errno() != missing: return PagedIoResult[bool](status: FileError.IoFailure)
  PagedIoResult[bool](status: FileError.None, completed: false)
proc removePinned*(directory: PagedDirectory, file: PagedFile): FileError =
  ## The wrapper validates selected/retired authority; this layer additionally demands an independent exclusive pin.
  let checked = directory.check
  if checked != FileError.None: return checked
  let verified = file.check
  if verified != FileError.None: return verified
  let a = directory.data
  let b = file.data
  assert a != nil and b != nil
  if not a.writer or not b.exclusive or not directory.sameDirectory(
      file): return FileError.WrongIdentity
  var name = b.name
  if unlinkAt(a.fd, name.toCString(), 0) != 0: return FileError.IoFailure
  if sync(a.fd) != 0: return FileError.PublishedUnsynced
  FileError.None
proc initialAbsent*(directory: PagedDirectory): FileError =
  ## Bootstrap may never overwrite an unexpected existing CURRENT, even in a newly created namespace.
  let checked = directory.check
  if checked != FileError.None: return checked
  let data = directory.data
  assert data != nil
  var metadata = default(Stat)
  if named(data.fd, "CURRENT", metadata): return FileError.AlreadyExists
  if posix.errno() != missing: return FileError.IoFailure
  FileError.None
proc matchesDirectory*(directory: PagedDirectory, receipt: PagedFileIdentity): bool =
  ## Already-absent retries still require the exact captured namespace inode.
  let data = directory.data
  if data == nil or not data.active or not receipt.ready: return false
  same(data.identity, receipt.directory)

proc truncateNative(fd: cint, extent: int64): cint {.importc: "ftruncate", cdecl,
    header: "<unistd.h>".}
  ## Supported Linux/macOS SDKs supply 64-bit off_t for one private anonymous workspace file.
proc openGraphScratch(file: var PagedFile, directory: PagedDirectory, extent: uint64,
    limit: ByteLimit): FileError =
  ## Sparse private extent reservation is constant-space; graph admission explicitly initializes every flag.
  if extent > uint64(limit) or extent > uint64(high(int64)): return FileError.LimitExceeded
  let created = openTemporary(file, directory, limit, false, false)
  if created != FileError.None: return created
  let data = file.data
  assert data != nil
  var status = -1.cint
  while status != 0:
    # Repeating the identical anonymous extent after EINTR is idempotent and never changes a selected file.
    status = truncateNative(data.fd, int64(extent))
    if status != 0 and posix.errno() != interrupted:
      data.poisoned = true
      return FileError.IoFailure
  data.size = extent
  file.check
proc graphScratch(data: FileData): FullPagedScratch =
  ## Internal random writes are exposed only synchronously to full admission, never as exported callbacks.
  proc write(offset: PagedOffset, bytes: openArray[byte]): bool {.closure.} =
    ## Scratch has one anonymous exclusive owner and never grows beyond its admitted exact extent.
    let start = uint64(offset)
    if not data.active or data.poisoned or not data.anonymous or data.sealed or not identity(data):
      data.poisoned = true
      return false
    if start > data.size or uint64(bytes.len) > data.size-start: return false
    if seekNative(data.fd, int64(start), SEEK_SET) != int64(start) or not writeAll(data.fd, bytes):
      data.poisoned = true
      return false
    true
  FullPagedScratch(input: input(data), write: write)
proc readFullHeader*(file: var PagedFile, chain: StorageChainId, root: StateRoot,
    limits: PagedLimits): PagedIoResult[FullPagedResult[FullPagedHeader]] =
  ## One fixed header read precedes complete admission; source identity and EOF remain held by this owner.
  let checked = file.check
  if checked != FileError.None:
    return PagedIoResult[FullPagedResult[FullPagedHeader]](status: checked)
  let data = file.data
  assert data != nil
  if data.size < uint64(PagedPageBytes):
    return PagedIoResult[FullPagedResult[FullPagedHeader]](status: FileError.UnsupportedLayout)
  var raw = default(array[PagedPageBytes, byte])
  let source = input(data)
  assert source.read != nil
  if not source.read(PagedOffset(0), raw):
    return PagedIoResult[FullPagedResult[FullPagedHeader]](status: FileError.IoFailure)
  PagedIoResult[FullPagedResult[FullPagedHeader]](status: FileError.None,
    completed: decodeFullPagedHeader(raw, chain, root, limits))
proc validateFullFile*(file: var PagedFile, directory: PagedDirectory, header: FullPagedHeader,
    selected: FullPagedManifest, limits: FullPagedStreamLimits): PagedIoResult[
        FullPagedStreamResult[CheckedFullPagedArtifact]] =
  ## Anonymous scratch is freshly owned and always retired; checked metadata retains no descriptors or callbacks.
  let data = file.data
  if data == nil or not data.active or not header.initialized:
    return PagedIoResult[FullPagedStreamResult[CheckedFullPagedArtifact]](
        status: FileError.Uninitialized)
  if not directory.sameDirectory(file):
    return PagedIoResult[FullPagedStreamResult[CheckedFullPagedArtifact]](
        status: FileError.WrongIdentity)
  let policy = validateFullPagedPolicy(limits)
  if policy != FullPagedStreamError.None:
    let refused = validateFullPaged(default(PagedInput), default(FullPagedScratch), header,
        selected, limits)
    return PagedIoResult[FullPagedStreamResult[CheckedFullPagedArtifact]](status: FileError.None,
      completed: refused)
  if header.geometry.entries > uint64(limits.scratchBytes) div 2:
    return PagedIoResult[FullPagedStreamResult[CheckedFullPagedArtifact]](
        status: FileError.LimitExceeded)
  var temporary = default(PagedFile)
  defer:
    # Native retirement uncertainty overrides a successful graph result before it can grant a retained reader.
    if temporary.opened and temporary.close != FileError.None:
      result = PagedIoResult[FullPagedStreamResult[CheckedFullPagedArtifact]](
          status: FileError.IoFailure)
  let opened = openGraphScratch(temporary, directory, header.geometry.entries*2,
      limits.scratchBytes)
  if opened != FileError.None:
    return PagedIoResult[FullPagedStreamResult[CheckedFullPagedArtifact]](status: opened)
  let workspace = temporary.data
  assert workspace != nil
  let admitted = validateFullPaged(input(data), graphScratch(workspace), header, selected, limits)
  if admitted.error in {FullPagedStreamError.IOFailure, FullPagedStreamError.ChangedInput}:
    # Source identity checks decide whether the held source also needs poisoning after a scratch-only failure.
    if not identity(data): data.poisoned = true
  PagedIoResult[FullPagedStreamResult[CheckedFullPagedArtifact]](status: FileError.None,
      completed: admitted)
proc lookupFullFile*(file: var PagedFile, checked: CheckedFullPagedArtifact, root: StateRoot,
    key: StateKey): FullPagedStreamResult[FullPagedLookup] =
  ## Independently owned lookup bytes survive retirement of this immutable native epoch pin.
  let data = file.data
  if data == nil or not data.active:
    return lookupFullPaged(default(PagedInput), checked, root, key)
  let found = lookupFullPaged(input(data), checked, root, key)
  if found.error in {FullPagedStreamError.IOFailure, FullPagedStreamError.ChangedInput}:
    if not identity(data): data.poisoned = true
  found

proc sealFull(data: FileData, built: FullPagedBuildResult): PagedIoResult[FullPagedBuildResult] =
  ## Share exact final stat/sealing behavior for streamed construction and source-derived physical compaction.
  if built.error == FullPagedBuildError.None:
    # A fresh immutable version capture precedes any native sealed-artifact capability.
    var metadata = default(Stat)
    if posix.fstat(data.fd, metadata) != 0:
      data.poisoned = true
      return PagedIoResult[FullPagedBuildResult](status: FileError.IoFailure)
    data.identity = metadata
    data.sealed = true
  PagedIoResult[FullPagedBuildResult](status: FileError.None, completed: built)
proc buildFullFile*(file: var PagedFile, directory: PagedDirectory, producer: nil FullPagedProducer,
    header: FullPagedHeader, limits: FullPagedBuildLimits): PagedIoResult[FullPagedBuildResult] =
  ## Author only a fresh exclusive empty target; complete graph admission precedes native sealing.
  let data = file.data
  if data == nil or not data.active or data.poisoned or data.sealed or not data.exclusive:
    return PagedIoResult[FullPagedBuildResult](status: FileError.RecoveryRequired)
  if not header.initialized or not directory.sameDirectory(file):
    return PagedIoResult[FullPagedBuildResult](status: FileError.WrongIdentity)
  if header.geometry.entries > uint64(limits.admission.scratchBytes) div 2:
    return PagedIoResult[FullPagedBuildResult](status: FileError.LimitExceeded)
  var temporary = default(PagedFile)
  defer:
    # An uncertain workspace close cannot grant a sealed-artifact receipt.
    if temporary.opened and temporary.close != FileError.None:
      result = PagedIoResult[FullPagedBuildResult](status: FileError.IoFailure)
  let opened = openGraphScratch(temporary, directory, header.geometry.entries*2,
      limits.admission.scratchBytes)
  if opened != FileError.None: return PagedIoResult[FullPagedBuildResult](status: opened)
  let workspace = temporary.data
  assert workspace != nil
  let built = buildFullPaged(PagedOutput(source: input(data), append: appender(data)),
    graphScratch(workspace), producer, header, limits)
  sealFull(data, built)

proc compactFullFile*(file: var PagedFile, source: var PagedFile, directory: PagedDirectory,
    checked: CheckedFullPagedArtifact, target: FullPagedHeader,
    limits: FullPagedCompactionLimits): PagedIoResult[FullPagedBuildResult] =
  ## Independent immutable source and exclusive fresh target owners remain held throughout authenticated rewriting.
  let data = file.data
  let original = source.data
  if data == nil or original == nil or not data.active or not original.active:
    return PagedIoResult[FullPagedBuildResult](status: FileError.Uninitialized)
  if data.poisoned or data.sealed or not data.exclusive or original.poisoned or not original.sealed:
    return PagedIoResult[FullPagedBuildResult](status: FileError.RecoveryRequired)
  if not checked.initialized or not directory.sameDirectory(file) or not directory.sameDirectory(source):
    return PagedIoResult[FullPagedBuildResult](status: FileError.WrongIdentity)
  let policy = checked.limits
  let shape = checked.header.geometry
  if shape.entries > uint64(policy.scratchBytes) div 2:
    return PagedIoResult[FullPagedBuildResult](status: FileError.LimitExceeded)
  var temporary = default(PagedFile)
  defer:
    # Workspace close uncertainty cannot produce a sealed native compaction receipt.
    if temporary.opened and temporary.close != FileError.None:
      result = PagedIoResult[FullPagedBuildResult](status: FileError.IoFailure)
  let opened = openGraphScratch(temporary, directory, shape.entries*2, policy.scratchBytes)
  if opened != FileError.None: return PagedIoResult[FullPagedBuildResult](status: opened)
  let workspace = temporary.data
  assert workspace != nil
  let built = compactFullPaged(PagedOutput(source: input(data), append: appender(data)),
    input(original), graphScratch(workspace), checked, target, limits)
  sealFull(data, built)

proc streamFullEntries*(file: var PagedFile, checked: CheckedFullPagedArtifact, root: StateRoot,
    visitor: nil FullPagedEntryVisitor, budget: FullPagedWorkLimits): FullPagedStreamResult[
        FullPagedCounts] =
  ## Hold the exact immutable native file throughout synchronous value borrowing; no graph scratch or callbacks survive.
  let data = file.data
  if data == nil or not data.active:
    return streamFullPagedEntries(default(PagedInput), checked, root, visitor, budget)
  let streamed = streamFullPagedEntries(input(data), checked, root, visitor, budget)
  if streamed.error in {FullPagedStreamError.IOFailure, FullPagedStreamError.ChangedInput}:
    if not identity(data): data.poisoned = true
  streamed
