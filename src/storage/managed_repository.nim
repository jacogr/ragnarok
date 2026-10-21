# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A stable directory lease selects one complete snapshot and its exact append journal.
## Opening validates every selected byte and graph; no directory scan or older-epoch fallback grants authority.
import std/assertions
import ./[file_errors, managed_io, managed_manifest, snapshot_codec, node_repository,
  node_records, journal_codec, database_identity, durability]
import ../codec/[bounded, state_trie]

type
  ManagedLimits* = object ## Physical file bounds remain independent of complete graph and context ceilings.
    repository*: RepositoryLimits
    roots*: ElementLimit
    snapshotBytes*, journalBytes*, contextBytes*: ByteLimit
  ManagedResult*[T] = object ## Failed/default operations expose reasons without a candidate revision.
    case status: FileError
    of None: completed: T
    of InvalidBatch: batchReason: RepositoryResult[RepositoryView]
    of InvalidFrame: frameReason: FrameError
    else: discard
  ManagedRepository* = object ## One explicit retirement owner serializes snapshot, append and epoch selection.
    directory: ManagedDirectory
    journal: ManagedJournal
    memory: NodeRepository
    context: seq[byte]
    chain: StorageChainId
    schema: StorageSchema
    epoch: ManagedEpoch
    limits: ManagedLimits
    active, poisoned: bool

proc `=copy`*(destination: var ManagedRepository, source: ManagedRepository) {.error.}
  ## Native leases cannot be implicitly duplicated by ARC.
proc `=dup`*(source: ManagedRepository): ManagedRepository {.error.}
  ## Actual lowering must reject a second retirement authority.
proc requireClosed(repository: ManagedRepository) {.requires: not repository.active.} =
  ## Close remains explicit while native failures can be reported.
  discard
proc `=destroy`*(repository: ManagedRepository) =
  ## Native owners enforce their own retirement even after a failed initialization.
  requireClosed(repository)
  `=destroy`(repository.journal)
  `=destroy`(repository.directory)
  `=destroy`(repository.memory)
  `=destroy`(repository.context)
func error*[T](outcome: ManagedResult[T]): FileError =
  ## Inspect the selected outer refusal alone.
  outcome.status
func value*[T](outcome: ManagedResult[T]): T {.inline, requires: outcome.status ==
    FileError.None.} =
  ## Only a fully completed operation exposes its payload.
  outcome.completed
func batchFailure*[T](outcome: ManagedResult[T]): RepositoryResult[RepositoryView] {.requires:
    outcome.status == FileError.InvalidBatch.} =
  ## Retain the actual failed preparation rather than fabricating a repository result.
  outcome.batchReason
func frameError*[T](outcome: ManagedResult[T]): FrameError {.requires:
    outcome.status == FileError.InvalidFrame.} =
  ## Expose only the selected frame failure.
  outcome.frameReason
func opened*(repository: ManagedRepository): bool =
  ## Lifecycle polling reads a scalar; graph access still requires exclusive owner access.
  repository.active
func snapshotLimits(limits: ManagedLimits): SnapshotLimits =
  ## Preserve the caller's complete graph policy verbatim across snapshot admission.
  SnapshotLimits(repository: limits.repository, roots: limits.roots,
    context: limits.contextBytes, bytes: limits.snapshotBytes)
func snapshotFailure(reason: SnapshotError): FileError =
  ## Classify identity/budget/backend errors without accepting a malformed snapshot prefix.
  case reason
  of SnapshotError.WrongIdentity: FileError.WrongIdentity
  of SnapshotError.LimitExceeded: FileError.LimitExceeded
  of SnapshotError.BackendFailure: FileError.BackendFailure
  else: FileError.InvalidJournal
proc retire(repository: var ManagedRepository): FileError =
  ## Failed acquisition and explicit close release each native resource exactly once.
  var reason = FileError.None
  if repository.journal.opened: reason = repository.journal.close
  if repository.directory.opened:
    let closed = repository.directory.close
    if reason == FileError.None: reason = closed
  if repository.memory.opened: discard repository.memory.close
  repository.context = @[]
  repository.active = false
  reason
proc close*(repository: var ManagedRepository): FileError =
  ## Retained immutable views survive explicit native retirement.
  if not repository.active: return FileError.Uninitialized
  retire(repository)
proc snapshot*(repository: ManagedRepository): ManagedResult[RepositoryView] =
  ## Uncertain IO refuses fresh reads without revoking previously held immutable views.
  if not repository.active: return ManagedResult[RepositoryView](status: FileError.Uninitialized)
  if repository.poisoned: return ManagedResult[RepositoryView](status: FileError.RecoveryRequired)
  ManagedResult[RepositoryView](status: FileError.None, completed: repository.memory.snapshot.value)
proc snapshotContext*(repository: ManagedRepository): ManagedResult[seq[byte]] =
  ## Return detached metadata from the same serialized selected revision.
  if not repository.active: return ManagedResult[seq[byte]](status: FileError.Uninitialized)
  if repository.poisoned: return ManagedResult[seq[byte]](status: FileError.RecoveryRequired)
  var context = newSeq[byte](repository.context.len)
  for index, octet in repository.context: context[index] = octet
  ManagedResult[seq[byte]](status: FileError.None, completed: context)
proc physicalEpoch*(repository: ManagedRepository): ManagedResult[ManagedEpoch] =
  ## Physical generations never masquerade as state publication generations.
  if not repository.active: return ManagedResult[ManagedEpoch](status: FileError.Uninitialized)
  if repository.poisoned: return ManagedResult[ManagedEpoch](status: FileError.RecoveryRequired)
  ManagedResult[ManagedEpoch](status: FileError.None, completed: repository.epoch)
proc initializeManagedRepository*(repository: var ManagedRepository, path: string,
    chain: StorageChainId, selection: RepositorySelection, context: openArray[byte],
    limits: ManagedLimits, schema = StorageSchema.FullNodesV1): FileError =
  ## Preflight a complete nonzero-generation seed before creating an absent managed directory.
  if repository.active: return FileError.Busy
  let encoded = encodeRepositorySnapshot(selection, chain, schema, context, snapshotLimits(limits))
  if encoded.error != SnapshotError.None: return snapshotFailure(encoded.error)
  let restored = decodeRepositorySnapshot(encoded.value.bytes, chain, schema, snapshotLimits(limits))
  if restored.error != SnapshotError.None: return snapshotFailure(restored.error)
  let manifest = encodeManagedManifest(chain, schema, ManagedEpoch(1), selection.generation,
    selection.commitment.root, encoded.value.checksum, ByteLimit(ManagedManifestBytes))
  if manifest.error != ManifestError.None: return FileError.BackendFailure
  let header = encodeManagedJournalHeader(manifest.value.checksum, limits.journalBytes)
  if header.error != ManifestError.None: return FileError.LimitExceeded
  var adopted = false
  defer:
    if not adopted: discard retire(repository) # Failed creation preserves its forensic files, but no lock.
  var reason = initializeManagedDirectory(repository.directory, path)
  if reason != FileError.None: return reason
  reason = createManagedFile(repository.directory, ManagedFileKind.Snapshot, ManagedEpoch(1),
    encoded.value.bytes, limits.snapshotBytes)
  if reason != FileError.None: return reason
  reason = createManagedFile(repository.directory, ManagedFileKind.Journal, ManagedEpoch(1),
    header.value, limits.journalBytes)
  if reason != FileError.None: return reason
  let journal = openManagedJournal(repository.journal, repository.directory, ManagedEpoch(1),
    limits.journalBytes)
  if journal.error != FileError.None: return journal.error
  if journal.value != header.value: return FileError.InvalidJournal
  reason = replaceManagedManifest(repository.directory, manifest.value.bytes, ByteLimit(ManagedManifestBytes))
  if reason != FileError.None: return reason
  repository.memory = restored.value.repository
  repository.context = restored.value.context
  repository.chain = chain
  repository.schema = schema
  repository.epoch = ManagedEpoch(1)
  repository.limits = limits
  repository.poisoned = false
  repository.active = true # Only the synchronized manifest grants a selected live revision.
  adopted = true
  FileError.None
proc openManagedRepository*(repository: var ManagedRepository, path: string, chain: StorageChainId,
    limits: ManagedLimits, schema = StorageSchema.FullNodesV1): FileError =
  ## Strictly validate exactly CURRENT's epoch; unknown and staged files are never recovery authority.
  if repository.active: return FileError.Busy
  var adopted = false
  defer:
    if not adopted: discard retire(repository) # Every refused graph/frame/identity releases both leases.
  let acquired = openManagedDirectory(repository.directory, path)
  if acquired != FileError.None: return acquired
  let current = readManagedFile(repository.directory, ManagedFileKind.Current, ManagedEpoch(0),
    ByteLimit(ManagedManifestBytes))
  if current.error != FileError.None: return current.error
  let decoded = decodeManagedManifest(current.value, chain, schema, ByteLimit(ManagedManifestBytes))
  if decoded.error == ManifestError.WrongIdentity: return FileError.WrongIdentity
  if decoded.error == ManifestError.BackendFailure: return FileError.BackendFailure
  if decoded.error != ManifestError.None: return FileError.InvalidJournal
  let manifest = decoded.value
  let bytes = readManagedFile(repository.directory, ManagedFileKind.Snapshot, manifest.epoch,
    limits.snapshotBytes)
  if bytes.error != FileError.None: return bytes.error
  let restored = decodeRepositorySnapshot(bytes.value, chain, schema, snapshotLimits(limits))
  if restored.error != SnapshotError.None: return snapshotFailure(restored.error)
  var memory = restored.value.repository
  let base = memory.snapshot.value
  let checksumMatches = array[32, byte](manifest.snapshotChecksum) == array[32, byte](
      restored.value.checksum)
  if not checksumMatches or uint64(base.generation) != uint64(manifest.generation) or
      array[32, byte](base.commitment.root) != array[32, byte](manifest.root):
    return FileError.InvalidJournal
  let journal = openManagedJournal(repository.journal, repository.directory, manifest.epoch,
    limits.journalBytes)
  if journal.error != FileError.None: return journal.error
  let frames = journal.value
  if frames.len < ManagedJournalHeaderBytes: return FileError.InvalidJournal
  if validateManagedJournalHeader(frames.toOpenArray(0, ManagedJournalHeaderBytes-1),
      manifest.checksum) != ManifestError.None: return FileError.InvalidJournal
  var offset = ManagedJournalHeaderBytes
  var context = restored.value.context
  while offset < frames.len:
    let extent = journalFrameExtent(frames.toOpenArray(offset, frames.high), limits.journalBytes)
    if extent.error != FrameError.None: return FileError.InvalidJournal
    let frame = if schema == StorageSchema.FullStateV1:
      decodeContextJournalFrame(frames.toOpenArray(offset, offset+extent.value-1),
        limits.contextBytes, limits.repository.codec, limits.journalBytes)
    else:
      decodeJournalFrame(frames.toOpenArray(offset, offset+extent.value-1),
        limits.repository.codec, limits.journalBytes) # Schema is chosen independently before decoding.
    if frame.error == FrameError.BackendFailure: return FileError.BackendFailure
    if frame.error != FrameError.None: return FileError.InvalidJournal
    let selected = memory.snapshot.value
    if uint64(selected.generation) == high(uint64) or
        uint64(frame.value.generation) != uint64(selected.generation)+1: return FileError.InvalidJournal
    if memory.publish(selected, frame.value.batch).error != RepositoryError.None:
      return FileError.InvalidJournal
    context = frame.value.context # Only a completely admitted contiguous frame selects context.
    offset += extent.value
  repository.memory = memory
  repository.context = context
  repository.chain = chain
  repository.schema = schema
  repository.epoch = manifest.epoch
  repository.limits = limits
  repository.poisoned = false
  repository.active = true
  adopted = true
  FileError.None
