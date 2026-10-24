# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Directory-relative bounded paged IO with separate writer leases and immutable-epoch flock pins.
## Resources are explicit-close/move-only. Independent epoch directory descriptors survive writer retirement.
import std/assertions
import std/posix/posix
import ./[paged_codec, paged_stream, managed_manifest, file_errors]
import ../codec/[bounded, state_layout]

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
    active, poisoned, sealed, exclusive: bool
    name: string
    identity, namespace: Stat
    size: uint64
    limit: ByteLimit
  PagedFile* = object ## Unique epoch descriptor and independent directory descriptor, with one immutable native pin.
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
  posix.fstat(data.fd, held) == 0 and S_ISREG(held.st_mode) and held.st_size >= 0 and
    posix.fstat(data.directory, directory) == 0 and same(directory, data.namespace) and
    named(data.directory, data.name, path) and S_ISREG(path.st_mode) and same(path,
        data.identity) and
    same(held, data.identity) and (not data.sealed or sameVersion(held, data.identity)) and uint64(
        held.st_size) == data.size and path.st_size == held.st_size
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
proc openEpoch*(file: var PagedFile, directory: PagedDirectory, epoch: ManagedEpoch,
    pin: PagedPin, limit: ByteLimit): FileError =
  ## Create/pin exactly one no-follow regular file; every file owns an independent held-directory descriptor.
  if file.opened: return FileError.Busy
  let checked = directory.check
  if checked != FileError.None: return checked
  let data = directory.data
  assert data != nil
  if pin != PagedPin.Shared and not data.writer: return FileError.WrongIdentity
  let named = epochName(epoch)
  if named.error != FileError.None: return named.error
  var name = named.value
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
proc readCurrent*(directory: PagedDirectory): PagedIoResult[seq[byte]] =
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
  if posix.fstat(fd, metadata) != 0 or not S_ISREG(metadata.st_mode) or metadata.st_size != PagedManifestBytes:
    return PagedIoResult[seq[byte]](status: FileError.UnsupportedLayout)
  var bytes = newSeq[byte](PagedManifestBytes)
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
  if built.error == PagedStreamError.None:
    var metadata = default(Stat)
    if posix.fstat(data.fd, metadata) != 0:
      data.poisoned = true
      return PagedIoResult[PagedStreamResult[CheckedPagedArtifact]](status: FileError.IoFailure)
    else:
      data.identity = metadata
      data.sealed = true
  PagedIoResult[PagedStreamResult[CheckedPagedArtifact]](status: FileError.None, completed: built)
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
proc replaceCurrent*(directory: PagedDirectory, bytes: openArray[byte],
    beforeRename: proc(): FileError {.closure.}): FileError =
  ## Stage/fsync/close/rename/fsync the exact bounded manifest; uncertain publication never grants a receipt.
  let checked = directory.pendingAbsent
  if checked != FileError.None: return checked
  let data = directory.data
  assert data != nil
  if not data.writer or bytes.len != PagedManifestBytes: return FileError.WrongIdentity
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
