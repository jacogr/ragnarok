# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A stable directory lease selects one complete snapshot and its exact append journal.
## Opening validates every selected byte and graph; no directory scan or older-epoch fallback grants authority.
import std/assertions
import ./[file_errors, managed_io, managed_manifest, snapshot_codec, node_repository,
  node_records, record_codec, journal_codec, database_identity, durability]
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
  ManagedUsage* = object ## Copied selected-file extents exclude unknown/staged/retired files and retained reader memory.
    epoch*: ManagedEpoch
    generation*: RepositoryGeneration
    root*: StateRoot
    storedNodes*: int
    snapshotBytes*, journalBytes*: uint64
  ManagedCompaction* = object ## Successful durable replacement reports deferred old-file cleanup separately.
    epoch*: ManagedEpoch
    generation*: RepositoryGeneration
    reclaimedNodes*: int
    reclaimedValueBytes*: uint64
    cleanup*: FileError
  ManagedRepository* = object ## One explicit retirement owner serializes snapshot, append and epoch selection.
    directory: ManagedDirectory
    journal: ManagedJournal
    memory: NodeRepository
    context: seq[byte]
    chain: StorageChainId
    schema: StorageSchema
    epoch: ManagedEpoch
    snapshotBytes: uint64
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
  let restored = cloneRepositorySelection(selection, limits.repository)
  if restored.error == RepositoryError.LimitExceeded: return FileError.LimitExceeded
  if restored.error != RepositoryError.None: return FileError.InvalidJournal
  var selectedContext = newSeq[byte](context.len)
  for index, octet in context: selectedContext[index] = octet # Borrowed application bytes never become a mutable alias.
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
  repository.memory = restored.value
  repository.context = selectedContext
  repository.chain = chain
  repository.schema = schema
  repository.epoch = ManagedEpoch(1)
  repository.snapshotBytes = uint64(encoded.value.bytes.len)
  repository.limits = limits
  repository.poisoned = false
  repository.active = true # Only the synchronized manifest grants a selected live revision.
  adopted = true
  FileError.None
proc incompleteTail(bytes: openArray[byte], offset: int, limit: ByteLimit, contextual: bool): bool =
  ## Explicit repair permits only a plausible incomplete final frame, never complete corrupt bytes.
  let remaining = bytes.len-offset
  if remaining < 8: return true
  var length = 0'u64
  for index in 0..<8: length = length or (uint64(bytes[offset+index]) shl (8*index))
  let maximum = min(uint64(limit), uint64(high(int)))
  let minimumBody = uint64(TrieExportHeaderBytes)+(if contextual: 8'u64 else: 0'u64)
  if maximum < 48 or length < minimumBody or length > maximum-48: return false
  length+48 > uint64(remaining)
proc acquire(repository: var ManagedRepository, path: string, chain: StorageChainId,
    limits: ManagedLimits, schema: StorageSchema, repair: bool,
    expectedGeneration: RepositoryGeneration, expectedRoot: StateRoot): FileError =
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
  var loadedSnapshot = readManagedFile(repository.directory, ManagedFileKind.Snapshot,
    manifest.epoch,
    limits.snapshotBytes)
  if loadedSnapshot.error != FileError.None: return loadedSnapshot.error
  let bytes = loadedSnapshot.takeValue # One detached buffer owns the complete synchronous decoder input.
  let restored = decodeRepositorySnapshot(bytes, chain, schema, snapshotLimits(limits))
  if restored.error != SnapshotError.None: return snapshotFailure(restored.error)
  var memory = restored.value.repository
  let base = memory.snapshot.value
  let checksumMatches = array[32, byte](manifest.snapshotChecksum) == array[32, byte](
      restored.value.checksum)
  if not checksumMatches or uint64(base.generation) != uint64(manifest.generation) or
      array[32, byte](base.commitment.root) != array[32, byte](manifest.root):
    return FileError.InvalidJournal
  var journal = openManagedJournal(repository.journal, repository.directory, manifest.epoch,
    limits.journalBytes)
  if journal.error != FileError.None: return journal.error
  let frames = journal.takeValue # Replay borrows this sole detached owner until all selected frames are admitted.
  if frames.len < ManagedJournalHeaderBytes: return FileError.InvalidJournal
  if validateManagedJournalHeader(frames.toOpenArray(0, ManagedJournalHeaderBytes-1),
      manifest.checksum) != ManifestError.None: return FileError.InvalidJournal
  var offset = ManagedJournalHeaderBytes
  var context = restored.value.context
  var partial = false
  while offset < frames.len:
    let extent = journalFrameExtent(frames.toOpenArray(offset, frames.high), limits.journalBytes)
    if extent.error != FrameError.None:
      if repair and incompleteTail(frames, offset, limits.journalBytes, schema ==
          StorageSchema.FullStateV1):
        partial = true
        break # The verified prefix still needs independent exact authorization before truncation.
      return FileError.InvalidJournal
    let selected = memory.snapshot.value
    let frame = if schema == StorageSchema.FullStateV1:
      memory.replayContextJournalFrame(selected, frames.toOpenArray(offset, offset+extent.value-1),
        limits.contextBytes, limits.journalBytes)
    else:
      memory.replayJournalFrame(selected, frames.toOpenArray(offset, offset+extent.value-1),
        limits.journalBytes) # Independent schema selection precedes checksum and complete graph admission.
    if frame.error == FrameError.BackendFailure: return FileError.BackendFailure
    if frame.error != FrameError.None: return FileError.InvalidJournal
    context = frame.value.context # Only a completely admitted contiguous frame selects context.
    offset += extent.value
  if repair:
    let selected = memory.snapshot.value
    if uint64(selected.generation) != uint64(expectedGeneration) or
        array[32, byte](selected.commitment.root) != array[32, byte](expectedRoot):
      return FileError.RecoveryMismatch
    if partial:
      let truncated = truncateManagedJournal(repository.journal, uint64(offset))
      if truncated != FileError.None: return truncated # No unverified suffix is ever silently discarded.
  repository.memory = memory
  repository.context = context
  repository.chain = chain
  repository.schema = schema
  repository.epoch = manifest.epoch
  repository.snapshotBytes = uint64(bytes.len)
  repository.limits = limits
  repository.poisoned = false
  repository.active = true
  adopted = true
  FileError.None
proc openManagedRepository*(repository: var ManagedRepository, path: string, chain: StorageChainId,
    limits: ManagedLimits, schema = StorageSchema.FullNodesV1): FileError =
  ## Normal restart requires every selected frame; incomplete tails require an explicit recovery call.
  acquire(repository, path, chain, limits, schema, false, RepositoryGeneration(0), default(StateRoot))
proc recoverManagedRepository*(repository: var ManagedRepository, path: string,
    chain: StorageChainId, limits: ManagedLimits, expectedGeneration: RepositoryGeneration,
        expectedRoot: StateRoot,
    schema = StorageSchema.FullNodesV1): FileError =
  ## Authorize only an exact independently retained complete prefix before truncating an incomplete append.
  acquire(repository, path, chain, limits, schema, true, expectedGeneration, expectedRoot)
proc publish*(repository: var ManagedRepository, expected: RepositoryView, batch: TrieExport,
    context: openArray[byte] = []): ManagedResult[RepositoryView] =
  ## Prepare privately, append and synchronize the bound journal, then expose the exact prepared revision.
  if not repository.active: return ManagedResult[RepositoryView](status: FileError.Uninitialized)
  if repository.poisoned: return ManagedResult[RepositoryView](status: FileError.RecoveryRequired)
  if uint64(context.len) > uint64(repository.limits.contextBytes) or
      (repository.schema == StorageSchema.FullNodesV1 and context.len != 0):
    return ManagedResult[RepositoryView](status: FileError.LimitExceeded)
  var selectedContext = newSeq[byte](context.len)
  for index, octet in context: selectedContext[index] = octet
  var working = repository.memory
  let prepared = working.publish(expected, batch)
  if prepared.error != RepositoryError.None:
    return ManagedResult[RepositoryView](status: FileError.InvalidBatch, batchReason: prepared)
  let size = managedJournalBytes(repository.journal)
  if size.error != FileError.None: return ManagedResult[RepositoryView](status: size.error)
  let maximum = min(uint64(repository.limits.journalBytes), uint64(high(int)))
  let remaining = ByteLimit(maximum-size.value) # The journal lease admitted its size under this ceiling.
  let frame = if repository.schema == StorageSchema.FullStateV1:
    encodeContextJournalFrame(prepared.value.generation, batch, selectedContext,
      repository.limits.contextBytes, repository.limits.repository.codec, remaining)
  else:
    encodeJournalFrame(prepared.value.generation, batch, repository.limits.repository.codec, remaining)
  if frame.error == FrameError.LimitExceeded:
    return ManagedResult[RepositoryView](status: FileError.LimitExceeded)
  if frame.error != FrameError.None:
    return ManagedResult[RepositoryView](status: FileError.InvalidFrame, frameReason: frame.error)
  var reason = synchronize(repository.directory)
  if reason == FileError.None: reason = appendManagedJournal(repository.journal, [])
  if reason == FileError.None: reason = appendManagedJournal(repository.journal, frame.value)
  if reason != FileError.None:
    repository.poisoned = true # Partial/uncertain bytes revoke fresh live operations until explicit reopen.
    return ManagedResult[RepositoryView](status: reason)
  repository.memory = working
  repository.context = selectedContext
  ManagedResult[RepositoryView](status: FileError.None, completed: prepared.value)
proc synchronize*(repository: var ManagedRepository): ManagedResult[StorageDurability] =
  ## Reconfirm the journal and stable directory boundaries; uncertainty requires reopening.
  if not repository.active: return ManagedResult[StorageDurability](status: FileError.Uninitialized)
  if repository.poisoned: return ManagedResult[StorageDurability](
      status: FileError.RecoveryRequired)
  var reason = appendManagedJournal(repository.journal, [])
  if reason == FileError.None: reason = synchronize(repository.directory)
  if reason != FileError.None:
    repository.poisoned = true
    return ManagedResult[StorageDurability](status: reason)
  ManagedResult[StorageDurability](status: FileError.None,
      completed: StorageDurability.FileAndDirectorySynced)
proc compact*(repository: var ManagedRepository, expected: RepositoryView,
    roots: openArray[StateRoot]): ManagedResult[ManagedCompaction] =
  ## Replace the physical epoch under one stable lease; state root/generation/context never advance.
  if not repository.active: return ManagedResult[ManagedCompaction](status: FileError.Uninitialized)
  if repository.poisoned: return ManagedResult[ManagedCompaction](
      status: FileError.RecoveryRequired)
  let selected = repository.memory.snapshot.value
  let currentPlan = selectRepositoryRoots(selected, [selected.commitment.root], ElementLimit(1))
  if currentPlan.error != RepositoryError.None:
    return ManagedResult[ManagedCompaction](status: FileError.InvalidRetention)
  if not currentPlan.value.matches(expected):
    return ManagedResult[ManagedCompaction](status: FileError.StaleView)
  if uint64(repository.epoch) == high(uint64):
    return ManagedResult[ManagedCompaction](status: FileError.EpochExhausted)
  let retained = selectRepositoryRoots(selected, roots, repository.limits.roots)
  if retained.error != RepositoryError.None:
    return ManagedResult[ManagedCompaction](status: FileError.InvalidRetention)
  let plan = retained.value
  let encoded = encodeRepositorySnapshot(plan, repository.chain, repository.schema,
    repository.context, snapshotLimits(repository.limits))
  if encoded.error != SnapshotError.None:
    return ManagedResult[ManagedCompaction](status: snapshotFailure(encoded.error))
  let restored = cloneRepositorySelection(plan, repository.limits.repository)
  if restored.error == RepositoryError.LimitExceeded:
    return ManagedResult[ManagedCompaction](status: FileError.LimitExceeded)
  if restored.error != RepositoryError.None:
    return ManagedResult[ManagedCompaction](status: FileError.InvalidRetention)
  let next = ManagedEpoch(uint64(repository.epoch)+1)
  let manifest = encodeManagedManifest(repository.chain, repository.schema, next,
    selected.generation,
    selected.commitment.root, encoded.value.checksum, ByteLimit(ManagedManifestBytes))
  if manifest.error != ManifestError.None:
    return ManagedResult[ManagedCompaction](status: FileError.BackendFailure)
  let header = encodeManagedJournalHeader(manifest.value.checksum, repository.limits.journalBytes)
  if header.error != ManifestError.None:
    return ManagedResult[ManagedCompaction](status: FileError.LimitExceeded)
  var journal = default(ManagedJournal)
  defer:
    if journal.opened: discard journal.close # Staging never retires the selected old journal on failure.
  var reason = createManagedFile(repository.directory, ManagedFileKind.Snapshot, next,
    encoded.value.bytes, repository.limits.snapshotBytes)
  if reason == FileError.None:
    reason = createManagedFile(repository.directory, ManagedFileKind.Journal, next,
      header.value, repository.limits.journalBytes)
  if reason != FileError.None:
    if reason != FileError.AlreadyExists: repository.poisoned = true
    return ManagedResult[ManagedCompaction](status: reason)
  let opened = openManagedJournal(journal, repository.directory, next,
      repository.limits.journalBytes)
  if opened.error != FileError.None:
    repository.poisoned = true
    return ManagedResult[ManagedCompaction](status: opened.error)
  if opened.value != header.value:
    repository.poisoned = true
    return ManagedResult[ManagedCompaction](status: FileError.InvalidJournal)
  reason = replaceManagedManifest(repository.directory, manifest.value.bytes, ByteLimit(ManagedManifestBytes))
  if reason != FileError.None:
    repository.poisoned = true # A visible replacement without confirmation never grants a live candidate.
    return ManagedResult[ManagedCompaction](status: reason)
  let prior = repository.epoch
  let closed = repository.journal.close
  let moved = moveManagedJournal(repository.journal, journal)
  repository.memory = restored.value # The private selected context remains byte-identical through physical replacement.
  repository.epoch = next
  repository.snapshotBytes = uint64(encoded.value.bytes.len)
  if closed != FileError.None or moved != FileError.None:
    repository.poisoned = true
    return ManagedResult[ManagedCompaction](status: FileError.RecoveryRequired)
  var cleanup = removeManagedFile(repository.directory, ManagedFileKind.Journal, prior)
  let removed = removeManagedFile(repository.directory, ManagedFileKind.Snapshot, prior)
  if cleanup == FileError.None: cleanup = removed # Cleanup cannot roll back a confirmed manifest selection.
  ManagedResult[ManagedCompaction](status: FileError.None, completed: ManagedCompaction(epoch: next,
    generation: selected.generation, reclaimedNodes: plan.reclaimableNodes,
    reclaimedValueBytes: plan.reclaimableValueBytes, cleanup: cleanup))
proc cleanupRetiredEpoch*(repository: var ManagedRepository, epoch: ManagedEpoch): FileError =
  ## Explicitly retry deletion of one caller-selected earlier epoch; never scan or remove the selected pair.
  if not repository.active: return FileError.Uninitialized
  if repository.poisoned: return FileError.RecoveryRequired
  if uint64(epoch) == 0 or uint64(epoch) >= uint64(
      repository.epoch): return FileError.InvalidRetention
  let journal = removeManagedFile(repository.directory, ManagedFileKind.Journal, epoch)
  if journal != FileError.None: return journal
  removeManagedFile(repository.directory, ManagedFileKind.Snapshot, epoch)
proc discardManagedStaging*(repository: var ManagedRepository): FileError =
  ## A validated selected owner may explicitly discard only CURRENT.next and its immediate unselected successor.
  if not repository.active: return FileError.Uninitialized
  if repository.poisoned: return FileError.RecoveryRequired
  if uint64(repository.epoch) == high(uint64): return FileError.EpochExhausted
  let pending = discardManagedPending(repository.directory)
  if pending != FileError.None: return pending
  let next = ManagedEpoch(uint64(repository.epoch)+1)
  let journal = removeManagedFile(repository.directory, ManagedFileKind.Journal, next)
  if journal != FileError.None: return journal
  removeManagedFile(repository.directory, ManagedFileKind.Snapshot, next)
proc usage*(repository: ManagedRepository): ManagedResult[ManagedUsage] =
  ## Inspect cached selected extents and scalar revision metadata without IO, hashing or graph detachment.
  if not repository.active: return ManagedResult[ManagedUsage](status: FileError.Uninitialized)
  if repository.poisoned: return ManagedResult[ManagedUsage](status: FileError.RecoveryRequired)
  let journal = managedJournalBytes(repository.journal)
  if journal.error != FileError.None: return ManagedResult[ManagedUsage](status: journal.error)
  let view = repository.memory.snapshot.value
  ManagedResult[ManagedUsage](status: FileError.None, completed: ManagedUsage(
    epoch: repository.epoch,
    generation: view.generation, root: view.commitment.root, storedNodes: view.storedNodes,
    snapshotBytes: repository.snapshotBytes, journalBytes: journal.value))
