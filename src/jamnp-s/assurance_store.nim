# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Single-writer per-shard durable storage keeps constant resident metadata; exact records and synchronized publication precede any stored-data receipt.
## Call only on a serialized managed I/O lease, preserve the private directory namespace and explicitly close before moving or destroying this native owner.
import std/[assertions, strutils]
import std/posix/posix
import ./[assurance_record, availability_proof]
import ../lib/atomic/file as atomic_file
import ../lib/atomic/file/writer
import ../codec/bounded
import ../state/availability/specifier
import ../state/erasure/words
import ../crypto/primitives

const IdentityMagic = "RAGAF001"
type
  AssuranceScanStop* = proc(context: nil pointer): bool {.nimcall, raises: [].}
    ## A trusted host reads cancellation only; the borrowed context outlives this synchronous call and grants no storage/signing authority.
  AssuranceScanControl* = object ## Optional non-owning cancellation is supplied at execution, never retained in the namespace or a queued job.
    stop: nil AssuranceScanStop
    context: nil pointer
  AssuranceStoreLimits* = object ## Logical serialized-record bytes, retained count, directory scan work and per-record verification are independent explicit policies.
    entries*, scanEntries*: ElementLimit
    bytes*: ByteLimit
    record*: AssuranceRecordLimits
  StoredAssuranceShard* = object ## Only successful publication or synchronized full restore constructs detached stored data; this is not current canonical duty or signing authority.
    ready: bool
    record: AssuranceRecord
  AssuranceStore* = object ## A fixed-address composite owns its identity lock and counters, never an archive-sized payload index or cache.
    gate: AtomicFileWriter
    folder: string
    chain: AssuranceChainId
    limits: AssuranceStoreLimits
    count, bytes: uint64
    observed: AssuranceTime
    ready, failed: bool
  AssuranceStoreError* {.pure.} = enum ## A failure/default contains no stored-data receipt or partially opened namespace.
    Uninitialized, None, Closed, Busy, Faulted, InvalidPolicy, InvalidPath, AlreadyExists,
    InvalidNamespace, Missing, InvalidRequest, Conflict, InvalidTime, LimitExceeded, Cancelled,
    FileFailure, HeaderFailure, RecordFailure, EncodingFailure, BackendFailure
  AssuranceStoreResult*[T] = object ## The actual failed filesystem, codec or primitive alternative remains selected.
    case status: AssuranceStoreError
    of None: completed: T
    of FileFailure: fileReason: AtomicFileError
    of HeaderFailure: headerReason: AssuranceRecordResult[AssuranceRecordInfo]
    of RecordFailure: recordReason: AssuranceRecordResult[AssuranceRecord]
    of EncodingFailure: encodingReason: AssuranceRecordResult[seq[byte]]
    of BackendFailure: cryptoReason: CryptoError
    else: discard # No simple refusal owns successful data or an unrelated child reason.
  ScanInfo = object ## Startup accumulates only scalar accounting and the largest already promised time.
    count, bytes, steps: uint64
    observed: AssuranceTime
proc `=copy`*(destination: var AssuranceStore, source: AssuranceStore) {.error.}
  ## Copies could unlock another owner or invalidate a managed borrow of this fixed address.
proc `=dup`*(source: AssuranceStore): AssuranceStore {.error.}
  ## Composite duplication is forbidden independently of the child writer's own ownership rules.
proc requireClosed(owner: AssuranceStore) {.requires: not owner.ready and not owner.gate.opened.} =
  ## Native exclusion must retire explicitly while Services and every managed borrower still exist.
  discard
proc `=wasMoved`*(owner: var AssuranceStore) {.nodestroy, inline, requires: not owner.ready and
    not owner.gate.opened.} =
  ## Only a closed owner may move; delegate every managed/native child move hook.
  owner.ready = false
  owner.failed = false
  `=wasMoved`(owner.gate)
  `=wasMoved`(owner.folder)
proc `=destroy`*(owner: AssuranceStore) =
  ## Explicit close owns native retirement; then child-managed strings may be destroyed normally.
  requireClosed(owner)
  `=destroy`(owner.gate)
  `=destroy`(owner.folder)
proc openDescriptor(path: cstring, flags: cint): cint {.importc: "open", cdecl,
    header: "<fcntl.h>".}
  ## Non-creation opens use the SDK's actual variadic ABI.
proc synchronizeDescriptor(descriptor: cint): cint {.importc: "fsync", cdecl, header: "<unistd.h>".}
  ## Maintained OS file/directory synchronization has an explicit result, never implicit success.
let noFollow {.importc: "O_NOFOLLOW", header: "<fcntl.h>".}: cint
  ## The private namespace refuses symlink records, directories and identity paths.
func error*[T](outcome: AssuranceStoreResult[T]): AssuranceStoreError =
  ## Read a status before selecting stored data or its actual failed child.
  outcome.status
func value*[T](outcome: AssuranceStoreResult[T]): T {.requires: outcome.status ==
    AssuranceStoreError.None.} =
  ## Defaults and refusals cannot expose a partially opened owner or successful receipt.
  outcome.completed
func fileError*[T](outcome: AssuranceStoreResult[T]): AtomicFileError {.requires: outcome.status ==
    AssuranceStoreError.FileFailure.} =
  ## Preserve visibility uncertainty separately from an ordinary prepublication refusal.
  outcome.fileReason
func headerError*[T](outcome: AssuranceStoreResult[T]): AssuranceRecordResult[
    AssuranceRecordInfo] {.requires: outcome.status == AssuranceStoreError.HeaderFailure.} =
  ## Preserve a genuine fixed-header verification failure without a payload claim.
  outcome.headerReason
func recordError*[T](outcome: AssuranceStoreResult[T]): AssuranceRecordResult[
    AssuranceRecord] {.requires: outcome.status == AssuranceStoreError.RecordFailure.} =
  ## Preserve an actual complete record preparation/verification failure.
  outcome.recordReason
func encodingError*[T](outcome: AssuranceStoreResult[T]): AssuranceRecordResult[seq[
    byte]] {.requires: outcome.status == AssuranceStoreError.EncodingFailure.} =
  ## A refused encoder contains no partially publishable bytes.
  outcome.encodingReason
func cryptoError*[T](outcome: AssuranceStoreResult[T]): CryptoError {.requires: outcome.status ==
    AssuranceStoreError.BackendFailure.} =
  ## Only identity checksum failure uses this primitive alternative.
  outcome.cryptoReason
func refused[T](reason: AssuranceStoreError): AssuranceStoreResult[T] {.requires: reason notin {
    AssuranceStoreError.None, AssuranceStoreError.FileFailure, AssuranceStoreError.HeaderFailure,
    AssuranceStoreError.RecordFailure, AssuranceStoreError.EncodingFailure,
    AssuranceStoreError.BackendFailure}.} =
  ## Simple refusals carry only a reason and no accepted prefix.
  AssuranceStoreResult[T](status: reason)
func fileFailure[T](reason: AtomicFileError): AssuranceStoreResult[T] {.requires: reason !=
    AtomicFileError.None.} =
  ## Only the actual failed filesystem boundary supplies this diagnostic.
  AssuranceStoreResult[T](status: AssuranceStoreError.FileFailure, fileReason: reason)
func propagated[T, U](outcome: AssuranceStoreResult[U]): AssuranceStoreResult[
    T] {.requires: outcome.status != AssuranceStoreError.None.} =
  ## Convert a genuine selected failure without retaining success data from another stage.
  case outcome.status
  of AssuranceStoreError.FileFailure: fileFailure[T](outcome.fileReason)
  of AssuranceStoreError.HeaderFailure: AssuranceStoreResult[T](
      status: AssuranceStoreError.HeaderFailure, headerReason: outcome.headerReason)
  of AssuranceStoreError.RecordFailure: AssuranceStoreResult[T](
      status: AssuranceStoreError.RecordFailure, recordReason: outcome.recordReason)
  of AssuranceStoreError.EncodingFailure: AssuranceStoreResult[T](
      status: AssuranceStoreError.EncodingFailure, encodingReason: outcome.encodingReason)
  of AssuranceStoreError.BackendFailure: AssuranceStoreResult[T](
      status: AssuranceStoreError.BackendFailure, cryptoReason: outcome.cryptoReason)
  of AssuranceStoreError.None: refused[T](AssuranceStoreError.Uninitialized) # Excluded by the checked precondition.
  else: refused[T](outcome.status)
func assuranceScanControl*(stop: AssuranceScanStop, context: nil pointer): AssuranceScanControl =
  ## The host owns this stable callback/context through the current synchronous execution only.
  AssuranceScanControl(stop: stop, context: context)
proc stopped*(control: AssuranceScanControl): bool =
  ## No control leaves the ordinary standalone API unchanged; an actual callback can only stop admission.
  let stop = control.stop
  if stop == nil: return false
  stop(control.context)
func valid*(limits: AssuranceStoreLimits): bool =
  ## The whole configured archive, 258 fixed namespace entries and one interrupted writer sibling must fit the independent scan ceiling; the preceding uint32 record bound proves addition safe.
  uint64(limits.entries) >= 1 and uint64(limits.entries) <= uint64(high(uint32)) and uint64(
      limits.scanEntries) >= uint64(limits.entries)+259 and uint64(limits.scanEntries) <= uint64(
          high(uint32)) and uint64(
      limits.bytes) >= uint64(AssuranceRecordHeaderBytes) and limits.record.valid and uint64(
      limits.record.verification.hashBytes) >= 174
func opened*(owner: AssuranceStore): bool =
  ## An opened namespace has completed identity and bounded accounting admission, not proof verification of every archived payload.
  owner.ready
func faulted*(owner: AssuranceStore): bool =
  ## Uncertain publication or failed recovery bars further stored-data receipts until close/reopen.
  owner.failed
func len*(owner: AssuranceStore): uint64 =
  ## Read scalar accounting only after the mutable managed store lease retires; Services may cache earlier values separately.
  owner.count
func byteLength*(owner: AssuranceStore): uint64 =
  ## Logical serialized-record bytes exclude directory/lock filesystem overhead.
  owner.bytes
func valid*(stored: StoredAssuranceShard): bool =
  ## A default result contains neither a durability boundary nor verified data.
  stored.ready
proc storedInfo*(stored: StoredAssuranceShard): AssuranceStoreResult[AssuranceRecordInfo] =
  ## Return copied metadata only; a receipt is not an assurance signing capability.
  if not stored.ready: return refused[AssuranceRecordInfo](AssuranceStoreError.Uninitialized)
  AssuranceStoreResult[AssuranceRecordInfo](status: AssuranceStoreError.None,
      completed: stored.record.recordInfo.value)
proc storedTransfer*(stored: StoredAssuranceShard, maximum: ByteLimit): AvailabilityTransferResult[
    VerifiedAvailabilityTransfer] =
  ## Serving gets an independent verified copy, not an alias into any store or prior worker lifetime.
  if not stored.ready: return detachVerifiedAvailability(default(VerifiedAvailabilityTransfer), maximum)
  stored.record.recordTransfer(maximum)
func parent(path: string): string =
  ## Preserve exact path selection while locating the directory whose new child name must become durable.
  var slash = -1
  for index, character in path:
    if character == '/': slash = index
  if slash < 0: "." elif slash == 0: "/" else: path.substr(0, slash-1)
proc syncDirectory(path: string): AtomicFileError =
  ## One checked directory descriptor is closed exactly once on success and every refusal path.
  var name = path
  let descriptor = openDescriptor(name.toCString(), O_RDONLY or O_CLOEXEC or O_NONBLOCK or noFollow)
  if descriptor < 0: return AtomicFileError.IoFailure
  var metadata = default(Stat)
  let correct = posix.fstat(descriptor, metadata) == 0 and S_ISDIR(metadata.st_mode)
  let synced = correct and synchronizeDescriptor(descriptor) == 0
  let closed = posix.close(descriptor) == 0
  if synced and closed: AtomicFileError.None else: AtomicFileError.PublishedUnsynced
func bucket(index: int): string =
  ## Exactly 256 lower-case hexadecimal buckets bound the root namespace independently of retained record count.
  const digits = "0123456789abcdef"
  assert index >= 0 and index < 256
  result = ""
  result.add(digits[index div 16])
  result.add(digits[index mod 16])
func recordName(info: AssuranceRecordInfo): string =
  ## Complete root and original E2 shard coordinates become fixed safe ASCII, never an input-derived path component.
  const digits = "0123456789abcdef"
  result = newString(75)
  for index, octet in info.specifier.erasureRoot.bytes:
    result[index*2] = digits[int(octet shr 4)]
    result[index*2+1] = digits[int(octet and 15)]
  result[64] = '-'
  let shard = uint64(info.shard)
  assert shard < 1023
  for index in 0..<4: result[65+index] = digits[int((shard shr ((3-index)*4)) and 15)]
  for index, character in ".shard": result[69+index] = character
func pathFor(owner: AssuranceStore, expected: AvailabilitySpecifier,
    shard: ErasureShardIndex): string =
  ## Public callers validate the shard bound before this fixed coordinate conversion.
  let name = recordName(AssuranceRecordInfo(specifier: expected, shard: shard))
  owner.folder & "/" & name.substr(0, 1) & "/" & name
proc regular(path: string): AssuranceStoreResult[uint64] =
  ## Only actual ENOENT is absence; symlinks, special files and permission/read failures cannot supply capacity or a record.
  var name = path
  var metadata = default(Stat)
  if posix.lstat(name.toCString(), metadata) != 0:
    if posix.errno() == ENOENT: return refused[uint64](AssuranceStoreError.Missing)
    return fileFailure[uint64](AtomicFileError.IoFailure)
  if not S_ISREG(metadata.st_mode) or metadata.st_size < 0: return refused[uint64](
      AssuranceStoreError.InvalidNamespace)
  AssuranceStoreResult[uint64](status: AssuranceStoreError.None, completed: uint64(
      metadata.st_size))
proc readHeader(path: string, chain: AssuranceChainId,
    limits: AssuranceRecordLimits): AssuranceStoreResult[AssuranceRecordInfo] =
  ## Startup reads only a fixed header, requires a regular exact-sized record and retains no payload or directory entry pointer.
  var name = path
  var descriptor = openDescriptor(name.toCString(), O_RDONLY or O_CLOEXEC or O_NONBLOCK or noFollow)
  if descriptor < 0: return fileFailure[AssuranceRecordInfo](AtomicFileError.IoFailure)
  defer:
    if descriptor >= 0: discard posix.close(descriptor) # Failed reads still retire their exact descriptor.
  var metadata = default(Stat)
  if posix.fstat(descriptor, metadata) != 0 or not S_ISREG(metadata.st_mode) or metadata.st_size < AssuranceRecordHeaderBytes:
    return refused[AssuranceRecordInfo](AssuranceStoreError.InvalidNamespace)
  if uint64(metadata.st_size) > uint64(limits.bytes): return refused[AssuranceRecordInfo](
      AssuranceStoreError.LimitExceeded)
  var header = default(array[AssuranceRecordHeaderBytes, byte])
  var used = 0
  while used < header.len:
    # The fixed remaining extent bounds every native read and offset before indexing scratch.
    let count = posix.read(descriptor, addr header[used], header.len-used)
    if count <= 0 or count > header.len-used: return fileFailure[AssuranceRecordInfo](
        AtomicFileError.IoFailure)
    used += count
  let closing = descriptor
  descriptor = -1
  if posix.close(closing) != 0: return fileFailure[AssuranceRecordInfo](AtomicFileError.IoFailure)
  let inspected = inspectAssuranceRecord(header, chain, limits)
  if inspected.error != AssuranceRecordError.None: return AssuranceStoreResult[AssuranceRecordInfo](
      status: AssuranceStoreError.HeaderFailure, headerReason: inspected)
  if inspected.value.encodedBytes != uint64(metadata.st_size): return refused[AssuranceRecordInfo](
      AssuranceStoreError.InvalidNamespace)
  AssuranceStoreResult[AssuranceRecordInfo](status: AssuranceStoreError.None,
      completed: inspected.value)
proc identity(chain: AssuranceChainId): AssuranceStoreResult[array[72, byte]] =
  ## The physical namespace version and independently selected chain are checksummed before creation.
  var wire = default(array[72, byte])
  for index in 0..<8: wire[index] = byte(IdentityMagic[index])
  for index in 0..<32: wire[8+index] = array[32, byte](chain)[index]
  let checksum = blake2b256(wire.toOpenArray(0, 39))
  if checksum.error != CryptoError.None: return AssuranceStoreResult[array[72, byte]](
      status: AssuranceStoreError.BackendFailure, cryptoReason: checksum.error)
  for index in 0..<32: wire[40+index] = array[32, byte](checksum.value)[index]
  AssuranceStoreResult[array[72, byte]](status: AssuranceStoreError.None, completed: wire)
proc checkIdentity(wire: seq[byte], chain: AssuranceChainId): AssuranceStoreResult[bool] =
  ## Opening never creates missing identity or adopts another chain or physical schema.
  if wire.len != 72: return refused[bool](AssuranceStoreError.InvalidNamespace)
  let expected = identity(chain)
  if expected.error != AssuranceStoreError.None: return propagated[bool, array[72, byte]](expected)
  for index in 0..<72:
    # Compare version, complete chain and checksum without alternate decoding or an accepted prefix.
    if wire[index] != expected.value[index]: return refused[bool](
        AssuranceStoreError.InvalidNamespace)
  AssuranceStoreResult[bool](status: AssuranceStoreError.None, completed: true)
func temporary(name: string, identityFile: bool): bool =
  ## Only the exact sibling pattern emitted by our atomic primitive is reclaimable after acquiring the global writer lease.
  let length = if identityFile: 8 else: 75
  if name.len != length+11: return false
  if identityFile and name.substr(0, 7) != "IDENTITY": return false
  if name.substr(length, length+4) != ".tmp.": return false
  for index in length+5..<name.len:
    if name[index] notin {'a'..'z', 'A'..'Z', '0'..'9'}: return false
  true
func recordSpelling(name: string): bool =
  ## Data names have one complete root, E2 shard ordinal and exact suffix; no traversal or hidden field is accepted.
  if name.len != 75 or name[64] != '-' or name.substr(69) != ".shard": return false
  for index in 0..<69:
    if index != 64 and name[index] notin {'0'..'9', 'a'..'f'}: return false
  var shard = 0
  for index in 65..<69:
    # Four admitted hexadecimal octets bound the parsed ordinal by 65535 before multiplication/addition.
    let digit = if name[index] in {'0'..'9'}: ord(name[index])-ord('0') else: ord(name[index])-ord('a')+10
    shard = shard*16+digit
  shard < 1023
proc removeTemporary(path: string): AssuranceStoreResult[bool] =
  ## Crash leftovers have never been canonical published record names; only regular sibling files may be removed.
  let selected = regular(path)
  if selected.error != AssuranceStoreError.None: return propagated[bool, uint64](selected)
  var name = path
  if posix.unlink(name.toCString()) != 0: return fileFailure[bool](AtomicFileError.IoFailure)
  AssuranceStoreResult[bool](status: AssuranceStoreError.None, completed: true)
proc scanDirectory(owner: AssuranceStore, folder: string, root: bool,
    info: var ScanInfo, control: AssuranceScanControl): AssuranceStoreResult[bool] =
  ## Public POSIX iteration preserves EOF versus failure and keeps only one copied entry/header in memory.
  if control.stopped: return refused[bool](AssuranceStoreError.Cancelled)
  var path = folder
  var metadata = default(Stat)
  if posix.lstat(path.toCString(), metadata) != 0 or not S_ISDIR(metadata.st_mode): return refused[
      bool](AssuranceStoreError.InvalidNamespace)
  var stream = default(DirStream)
  if openDirStream(stream, path.toCString()) < 0: return fileFailure[bool](
      AtomicFileError.IoFailure)
  var active = true
  defer:
    if active: discard closeDirStream(stream) # No failure can strand the directory's native read owner.
  var removed = false
  while true:
    # Entry names borrow the native buffer only until the next call; copied bounded names alone escape this iteration.
    if control.stopped: return refused[bool](AssuranceStoreError.Cancelled)
    var raw: cstring = ""
    var kind = 0'u8
    let next = nextDirEntry(stream, raw, kind)
    if next < 0: return fileFailure[bool](AtomicFileError.IoFailure)
    if next == 0: break
    let name = fromCString(raw)
    if name == "." or name == "..": continue
    if info.steps >= uint64(owner.limits.scanEntries): return refused[bool](
        AssuranceStoreError.LimitExceeded)
    inc info.steps
    let selected = folder & "/" & name
    if root:
      # A dedicated namespace admits only identity/lock, exact hex buckets and its own unpublished identity siblings.
      if name == "IDENTITY" or name == "IDENTITY.lock":
        let file = regular(selected)
        if file.error != AssuranceStoreError.None: return propagated[bool, uint64](file)
      elif name.len == 2 and name[0] in {'0'..'9', 'a'..'f'} and name[1] in {'0'..'9', 'a'..'f'}:
        var native = selected
        var child = default(Stat)
        if posix.lstat(native.toCString(), child) != 0 or not S_ISDIR(
            child.st_mode): return refused[bool](AssuranceStoreError.InvalidNamespace)
      elif name.startsWith("IDENTITY") and temporary(name, true):
        let deleted = removeTemporary(selected)
        if deleted.error != AssuranceStoreError.None: return deleted
        removed = true
      else: return refused[bool](AssuranceStoreError.InvalidNamespace)
    else:
      # Interrupted atomic siblings can be discarded; published names must match their authenticated fixed header exactly.
      if name.len == 86 and temporary(name, false) and recordSpelling(name.substr(0, 74)):
        let deleted = removeTemporary(selected)
        if deleted.error != AssuranceStoreError.None: return deleted
        removed = true
      else:
        if not recordSpelling(name): return refused[bool](AssuranceStoreError.InvalidNamespace)
        let inspected = readHeader(selected, owner.chain, owner.limits.record)
        if inspected.error != AssuranceStoreError.None: return propagated[bool,
            AssuranceRecordInfo](inspected)
        if recordName(inspected.value) != name or not folder.endsWith("/" & name.substr(0, 1)):
          return refused[bool](AssuranceStoreError.InvalidNamespace)
        if info.count >= uint64(owner.limits.entries) or inspected.value.encodedBytes > uint64(
            owner.limits.bytes)-info.bytes:
          return refused[bool](AssuranceStoreError.LimitExceeded)
        inc info.count
        info.bytes += inspected.value.encodedBytes
        info.observed = AssuranceTime(max(uint64(info.observed), uint64(
            inspected.value.promisedAt)))
  let closed = closeDirStream(stream)
  active = false
  if closed < 0: return fileFailure[bool](AtomicFileError.IoFailure)
  if removed:
    let synced = syncDirectory(folder)
    if synced != AtomicFileError.None: return fileFailure[bool](synced)
  AssuranceStoreResult[bool](status: AssuranceStoreError.None, completed: true)
proc close*(owner: var AssuranceStore): AssuranceStoreResult[bool] =
  ## Drop logical admission before retiring the exact writer lease; close remains idempotent after any failed setup or fault.
  owner.ready = false
  owner.failed = false
  let closed = owner.gate.close()
  owner.folder = ""
  owner.count = 0
  owner.bytes = 0
  owner.observed = AssuranceTime(0)
  if closed != AtomicFileError.None: return fileFailure[bool](closed)
  AssuranceStoreResult[bool](status: AssuranceStoreError.None, completed: true)
proc acquire(owner: var AssuranceStore, folder: string, chain: AssuranceChainId,
    limits: AssuranceStoreLimits, create: bool, control: AssuranceScanControl): AssuranceStoreResult[bool] =
  ## One explicit startup transaction establishes private namespace shape, chain identity, synchronization and bounded scalar accounting.
  if owner.ready or owner.gate.opened: return refused[bool](AssuranceStoreError.Busy)
  if not limits.valid: return refused[bool](AssuranceStoreError.InvalidPolicy)
  if control.stopped: return refused[bool](AssuranceStoreError.Cancelled)
  if folder.len == 0 or folder.len > 4000 or folder[folder.len-1] == '/': return refused[bool](
      AssuranceStoreError.InvalidPath)
  for character in folder:
    if character == char(0): return refused[bool](AssuranceStoreError.InvalidPath)
  var name = folder
  if create:
    # Creation never adopts or overwrites an existing directory, including a namespace with an incomplete identity.
    if posix.mkdir(name.toCString(), Mode(0o700)) != 0:
      if posix.errno() == EEXIST: return refused[bool](AssuranceStoreError.AlreadyExists)
      return fileFailure[bool](AtomicFileError.IoFailure)
  var metadata = default(Stat)
  if posix.lstat(name.toCString(), metadata) != 0 or not S_ISDIR(metadata.st_mode): return refused[
      bool](AssuranceStoreError.InvalidNamespace)
  owner.folder = ""
  for character in folder: owner.folder.add(character) # The native owner keeps independent path storage through every future worker lifetime.
  owner.chain = chain
  owner.limits = limits
  owner.failed = false
  defer:
    if not owner.ready: discard owner.close() # Failed admission cannot leave a writer, native borrower or partial logical owner live.
  let held = owner.gate.openAtomicFileWriter(owner.folder & "/IDENTITY")
  if held != AtomicFileError.None: return fileFailure[bool](held)
  if create:
    # All fixed bucket names exist before the complete identity becomes visible; the root and its parent are explicitly synchronized.
    for index in 0..<256:
      var path = owner.folder & "/" & bucket(index)
      if posix.mkdir(path.toCString(), Mode(0o700)) != 0: return fileFailure[bool](
          AtomicFileError.IoFailure)
      let synced = syncDirectory(path)
      if synced != AtomicFileError.None: return fileFailure[bool](synced)
    let encoded = identity(chain)
    if encoded.error != AssuranceStoreError.None: return propagated[bool, array[72, byte]](encoded)
    let written = createAtomicFile(owner.folder & "/IDENTITY", encoded.value, ByteLimit(72))
    if written != AtomicFileError.None: return fileFailure[bool](written)
  else:
    let file = owner.gate.read(ByteLimit(72))
    if file.error != AtomicFileError.None: return fileFailure[bool](file.error)
    let checked = checkIdentity(file.value, chain)
    if checked.error != AssuranceStoreError.None: return checked
  let confirmed = owner.gate.synchronize()
  if confirmed != AtomicFileError.None: return fileFailure[bool](confirmed)
  let parentSync = syncDirectory(parent(owner.folder))
  if parentSync != AtomicFileError.None: return fileFailure[bool](parentSync)
  var info = default(ScanInfo)
  let top = owner.scanDirectory(owner.folder, true, info, control)
  if top.error != AssuranceStoreError.None: return top
  for index in 0..<256:
    # Every known bucket must exist and finish enumeration; no directory failure can become a valid empty history.
    let checked = owner.scanDirectory(owner.folder & "/" & bucket(index), false, info, control)
    if checked.error != AssuranceStoreError.None: return checked
  if control.stopped: return refused[bool](AssuranceStoreError.Cancelled)
  owner.count = info.count
  owner.bytes = info.bytes
  owner.observed = info.observed
  owner.ready = true
  AssuranceStoreResult[bool](status: AssuranceStoreError.None, completed: true)
proc createAssuranceStore*(owner: var AssuranceStore, folder: string, chain: AssuranceChainId,
    limits: AssuranceStoreLimits, control = default(AssuranceScanControl)): AssuranceStoreResult[bool] =
  ## Only an explicitly requested fresh directory may initialize this independent availability database.
  owner.acquire(folder, chain, limits, true, control)
proc openAssuranceStore*(owner: var AssuranceStore, folder: string, chain: AssuranceChainId,
    limits: AssuranceStoreLimits, control = default(AssuranceScanControl)): AssuranceStoreResult[bool] =
  ## Existing storage must pass exact identity and complete bounded accounting before admission; missing identity is never recreated.
  owner.acquire(folder, chain, limits, false, control)
proc loadPath(owner: var AssuranceStore, path: string, expected: AvailabilitySpecifier,
    request: AvailabilityRequest): AssuranceStoreResult[StoredAssuranceShard] =
  ## Full data re-verification and file/parent synchronization, not header accounting, grant a restored stored-data receipt.
  let stat = regular(path)
  if stat.error != AssuranceStoreError.None: return propagated[StoredAssuranceShard, uint64](stat)
  if stat.value > uint64(owner.limits.record.bytes): return refused[StoredAssuranceShard](
      AssuranceStoreError.LimitExceeded)
  let file = readBoundedFile(path, owner.limits.record.bytes)
  if file.error != AtomicFileError.None:
    owner.failed = true
    return fileFailure[StoredAssuranceShard](file.error)
  let decoded = decodeAssuranceRecord(file.value, owner.chain, owner.limits.record)
  if decoded.error != AssuranceRecordError.None:
    owner.failed = true
    return AssuranceStoreResult[StoredAssuranceShard](status: AssuranceStoreError.RecordFailure,
        recordReason: decoded)
  if not decoded.value.recordMatches(expected, request): return refused[StoredAssuranceShard](
      AssuranceStoreError.Conflict)
  let confirmed = syncAtomicFile(path)
  if confirmed != AtomicFileError.None:
    owner.failed = true
    return fileFailure[StoredAssuranceShard](confirmed)
  AssuranceStoreResult[StoredAssuranceShard](status: AssuranceStoreError.None,
    completed: StoredAssuranceShard(ready: true, record: decoded.value))
proc loadAssuranceShard*(owner: var AssuranceStore, expected: AvailabilitySpecifier,
    request: AvailabilityRequest): AssuranceStoreResult[StoredAssuranceShard] =
  ## Only this live healthy namespace can grant a newly verified synchronized data receipt for exact independently selected metadata.
  if not owner.ready: return refused[StoredAssuranceShard](AssuranceStoreError.Closed)
  if owner.failed: return refused[StoredAssuranceShard](AssuranceStoreError.Faulted)
  let count = uint64(uint16(expected.erasureShards))
  if request.kind != AvailabilityTransferKind.Distribution or uint64(request.row) != 0 or uint64(
      request.shard) >= count or count > 1023 or request.root.bytes != expected.erasureRoot.bytes:
    return refused[StoredAssuranceShard](AssuranceStoreError.InvalidRequest)
  owner.loadPath(owner.pathFor(expected, request.shard), expected, request)
proc rememberAssuranceShard*(owner: var AssuranceStore, transfer: VerifiedAvailabilityTransfer,
    now: AssuranceTime): AssuranceStoreResult[StoredAssuranceShard] =
  ## Preserve old promises and refuse capacity before cloning/encoding; only successful file+directory sync publishes new counters and a receipt.
  if not owner.ready: return refused[StoredAssuranceShard](AssuranceStoreError.Closed)
  if owner.failed: return refused[StoredAssuranceShard](AssuranceStoreError.Faulted)
  if not transfer.valid or transfer.request.kind != AvailabilityTransferKind.Distribution:
    return refused[StoredAssuranceShard](AssuranceStoreError.InvalidRequest)
  if uint64(now) < uint64(owner.observed) or uint64(now) > high(
      uint64)-AssuranceRetentionSeconds: return refused[StoredAssuranceShard](
      AssuranceStoreError.InvalidTime)
  let specifier = transfer.specifier
  let request = transfer.request
  let path = owner.pathFor(specifier, request.shard)
  let present = regular(path)
  if present.error notin [AssuranceStoreError.None, AssuranceStoreError.Missing]: return propagated[
      StoredAssuranceShard, uint64](present)
  let replacing = present.error == AssuranceStoreError.None
  let previousBytes = if replacing: present.value else: 0'u64
  let required = uint64(AssuranceRecordHeaderBytes)+transfer.payloadBytes
  if previousBytes > owner.bytes: return refused[StoredAssuranceShard](
      AssuranceStoreError.InvalidNamespace)
  if not replacing and owner.count >= uint64(owner.limits.entries): return refused[
      StoredAssuranceShard](AssuranceStoreError.LimitExceeded)
  let used = owner.bytes-previousBytes
  if used > uint64(owner.limits.bytes) or required > uint64(
      owner.limits.bytes)-used: return refused[StoredAssuranceShard](
      AssuranceStoreError.LimitExceeded)
  var record = default(AssuranceRecord)
  if replacing:
    # Renewal verifies the original persisted context and keeps its payload; a same-root conflict never overwrites a previous promise.
    let old = owner.loadPath(path, specifier, request)
    if old.error != AssuranceStoreError.None: return old
    let renewed = renewAssuranceRecord(old.value.record, now, owner.limits.record)
    if renewed.error != AssuranceRecordError.None: return AssuranceStoreResult[
        StoredAssuranceShard](status: AssuranceStoreError.RecordFailure, recordReason: renewed)
    record = renewed.value
  else:
    let prepared = prepareAssuranceRecord(transfer, owner.chain, now, owner.limits.record)
    if prepared.error != AssuranceRecordError.None: return AssuranceStoreResult[
        StoredAssuranceShard](status: AssuranceStoreError.RecordFailure, recordReason: prepared)
    record = prepared.value
  let encoded = encodeAssuranceRecord(record, owner.limits.record)
  if encoded.error != AssuranceRecordError.None: return AssuranceStoreResult[StoredAssuranceShard](
      status: AssuranceStoreError.EncodingFailure, encodingReason: encoded)
  let published = replaceAtomicFile(path, encoded.value, owner.limits.record.bytes)
  if published != AtomicFileError.None:
    # Visibility uncertainty cannot leave a healthy owner publishing with stale capacity or claiming an unconfirmed promise.
    if published == AtomicFileError.PublishedUnsynced: owner.failed = true
    return fileFailure[StoredAssuranceShard](published)
  if not replacing: inc owner.count
  owner.bytes = used+uint64(encoded.value.len)
  owner.observed = now
  AssuranceStoreResult[StoredAssuranceShard](status: AssuranceStoreError.None,
    completed: StoredAssuranceShard(ready: true, record: record))
