# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit locked light journal owners publish immutable evidence only after confirmed sparse append durability.
import std/assertions
import ./[light_snapshot, light_state_cache, light_delta, light_journal_manifest,
  light_journal_replay, managed_io, managed_manifest, database_identity, file_errors, durability]
import ../codec/[bounded, state_trie, state_layout]
type
  LightJournalConfig* = object ## Independently selected trust and exact resource policies never come from journal metadata.
    chain*: StorageChainId
    root*: StateRoot
    snapshot*: LightSnapshotLimits
    journal*: LightReplayLimits
  LightJournalResult*[T] = object ## Default and failed operations expose no fresh reader or durability receipt.
    case status: FileError
    of None: completed: T
    else: discard
  JournalOwner = ref object ## One stable lease groups append descriptor, exact policy and last confirmed immutable image.
    directory: ManagedDirectory
    journal: ManagedJournal
    config: LightJournalConfig
    selected: LightJournalManifest
    image: PreparedLightSnapshot
    sequence: LightDeltaSequence
    frames: uint64
    poisoned: bool
  LightJournalCache* = object ## Move-only explicit retirement authority; immutable readers retain no native lease.
    data: nil JournalOwner
proc `=copy`*(destination: var LightJournalCache, source: LightJournalCache) {.error.}
  ## A composite cannot duplicate the sole directory and append retirement authority.
proc `=dup`*(source: LightJournalCache): LightJournalCache {.error.}
  ## Reject hidden owner duplication during actual ARC lowering.
proc requireClosed(owner: LightJournalCache) {.requires: owner.data == nil.} =
  ## Native retirement errors must be observed through explicit close.
  discard
proc `=destroy`*(owner: LightJournalCache) =
  ## Moved-from nil owners are inert; destroying a live lease without close is misuse.
  requireClosed(owner)
  `=destroy`(owner.data)
func error*[T](outcome: LightJournalResult[T]): FileError =
  ## Inspect refusal without granting a fresh successful payload.
  outcome.status
func value*[T](outcome: LightJournalResult[T]): T {.inline,
    requires: outcome.status == FileError.None.} =
  ## Extract only confirmed immutable readers, scalar metadata or durability receipts.
  outcome.completed
func opened*(owner: LightJournalCache): bool =
  ## Default and moved-from owners safely report their lifecycle.
  owner.data != nil
func fail[T](reason: FileError): LightJournalResult[T] =
  ## Failed results retain no old reader as a successful fresh observation.
  LightJournalResult[T](status: reason)
func lifecycle(data: nil JournalOwner): FileError =
  ## Every fresh operation refuses after uncertain IO until explicit close and strict reopen.
  if data == nil: FileError.Uninitialized
  elif data.poisoned: FileError.RecoveryRequired
  else: FileError.None
proc retire(data: JournalOwner): FileError =
  ## Close append before directory, preserve the first refusal, and always attempt both native retirements.
  let journal = data.journal.close
  let directory = data.directory.close
  if journal != FileError.None and journal != FileError.Uninitialized: return journal
  directory
proc close*(owner: var LightJournalCache): FileError =
  ## Disarm exactly once even when either native close refuses; retained readers remain independent.
  let data = owner.data
  if data == nil: return FileError.Uninitialized
  let reason = retire(data)
  owner.data = nil
  reason
func samePolicy(left, right: LightSnapshotLimits): bool =
  ## Preparation identity includes all inherited proof, image, cache and mutation ceilings.
  uint64(left.bytes) == uint64(right.bytes) and
    uint64(left.cache.items) == uint64(right.cache.items) and
    uint64(left.cache.writes) == uint64(right.cache.writes) and
    uint64(left.cache.valueBytes) == uint64(right.cache.valueBytes) and
    uint64(left.cache.proof.nodes) == uint64(right.cache.proof.nodes) and
    uint64(left.cache.proof.valueBytes) == uint64(right.cache.proof.valueBytes)
proc binding(image: PreparedLightSnapshot, config: LightJournalConfig): FileError =
  ## Opaque preparation cannot widen an owner's inherited policy or change its independent trust selection.
  if not image.initialized: return FileError.Uninitialized
  if array[32, byte](image.chainId) != array[32, byte](config.chain) or
      array[32, byte](image.root) != array[32, byte](config.root): return FileError.WrongIdentity
  if not samePolicy(image.limits, config.snapshot): return FileError.InvalidBatch
  FileError.None
func selectionReason(reason: LightSelectionError): FileError =
  ## Translate only selected schema refusals into the storage IO domain.
  case reason
  of LightSelectionError.None: FileError.None
  of LightSelectionError.Uninitialized: FileError.Uninitialized
  of LightSelectionError.LimitExceeded: FileError.LimitExceeded
  of LightSelectionError.WrongChain, LightSelectionError.WrongRoot: FileError.WrongIdentity
  of LightSelectionError.BackendFailure: FileError.BackendFailure
  else: FileError.InvalidJournal
func snapshotReason(reason: LightSnapshotError): FileError =
  ## A refused checkpoint never supplies a partially trusted starting image.
  case reason
  of LightSnapshotError.None: FileError.None
  of LightSnapshotError.WrongChain, LightSnapshotError.WrongRoot: FileError.WrongIdentity
  of LightSnapshotError.LimitExceeded, LightSnapshotError.LengthOverflow: FileError.LimitExceeded
  of LightSnapshotError.BackendFailure: FileError.BackendFailure
  else: FileError.InvalidFrame
func deltaReason(reason: LightDeltaError): FileError =
  ## Preserve policy/provider distinctions without granting failed proof or transition authority.
  case reason
  of LightDeltaError.None: FileError.None
  of LightDeltaError.Uninitialized: FileError.Uninitialized
  of LightDeltaError.LimitExceeded, LightDeltaError.LengthOverflow: FileError.LimitExceeded
  of LightDeltaError.WrongChain, LightDeltaError.WrongRoot: FileError.WrongIdentity
  of LightDeltaError.WrongBase, LightDeltaError.WrongSequence: FileError.StaleView
  of LightDeltaError.BackendFailure: FileError.BackendFailure
  else: FileError.InvalidBatch
func replayReason(outcome: LightReplayResult[LightJournalReplay]): FileError =
  ## Strict open never salvages a corrupt or incomplete suffix or retries another epoch.
  case outcome.error
  of LightReplayError.None: FileError.None
  of LightReplayError.LimitExceeded, LightReplayError.SequenceExhausted: FileError.LimitExceeded
  of LightReplayError.BackendFailure: FileError.BackendFailure
  of LightReplayError.InvalidSelection: selectionReason(outcome.selectionError)
  of LightReplayError.InvalidDelta: deltaReason(outcome.deltaError)
  of LightReplayError.WrongCheckpoint: FileError.WrongIdentity
  else: FileError.InvalidJournal
proc readSelection(data: JournalOwner): LightJournalResult[LightJournalManifest] =
  ## CURRENT uses one distinct bounded manifest schema, with no old-image or full-state fallback.
  var loaded = readManagedFile(data.directory, ManagedFileKind.Current, ManagedEpoch(0), ByteLimit(LightJournalManifestBytes))
  if loaded.error != FileError.None: return fail[LightJournalManifest](loaded.error)
  let decoded = decodeLightJournalManifest(loaded.value, data.config.chain, data.config.root,
      ByteLimit(LightJournalManifestBytes))
  let reason = selectionReason(decoded.error)
  if reason != FileError.None: return fail[LightJournalManifest](reason)
  LightJournalResult[LightJournalManifest](status: FileError.None, completed: decoded.value)
proc openLightJournalCache*(owner: var LightJournalCache, path: string,
    config: LightJournalConfig): FileError =
  ## Hold the directory and selected append inode while verifying the exact checkpoint, anchor and entire bounded log.
  if owner.opened: return FileError.Busy
  var data = JournalOwner(config: config)
  let acquired = openManagedDirectory(data.directory, path)
  if acquired != FileError.None: return acquired
  defer:
    if owner.data == nil: discard retire(data) # All refused opens release both resources without modifying forensic files.
  let selected = readSelection(data)
  if selected.error != FileError.None: return selected.error
  data.selected = selected.value
  var loaded = readManagedFile(data.directory, ManagedFileKind.Snapshot, data.selected.epoch,
      config.snapshot.bytes)
  if loaded.error != FileError.None: return loaded.error
  var encoded = loaded.takeValue
  let restored = takeLightSnapshot(encoded, config.chain, config.root, config.snapshot)
  let reason = snapshotReason(restored.error)
  if reason != FileError.None: return reason
  var journal = openManagedJournal(data.journal, data.directory, data.selected.epoch,
      config.journal.bytes)
  if journal.error != FileError.None: return journal.error
  var transport = journal.takeValue
  let replayed = replayLightJournal(transport, data.selected, restored.value, config.journal)
  let checked = replayReason(replayed)
  if checked != FileError.None: return checked
  data.image = replayed.value.snapshot
  data.sequence = replayed.value.sequence
  data.frames = replayed.value.frameCount
  owner.data = data
  FileError.None
proc initializeLightJournalCache*(owner: var LightJournalCache, path: string,
    config: LightJournalConfig, image: PreparedLightSnapshot): LightJournalResult[
        StorageDurability] =
  ## Create synchronized checkpoint and anchor before atomically selecting the new namespace; no partial owner escapes.
  if owner.opened: return fail[StorageDurability](FileError.Busy)
  let checked = binding(image, config)
  if checked != FileError.None: return fail[StorageDurability](checked)
  if uint64(config.journal.bytes) < uint64(LightJournalAnchorBytes): return fail[StorageDurability](
      FileError.LimitExceeded)
  let selected = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0),
      ByteLimit(LightJournalManifestBytes))
  if selected.error != LightSelectionError.None: return fail[StorageDurability](selectionReason(
      selected.error))
  let anchor = encodeLightJournalAnchor(selected.value, config.journal.bytes)
  if anchor.error != LightSelectionError.None: return fail[StorageDurability](selectionReason(anchor.error))
  var data = JournalOwner(config: config)
  let acquired = initializeManagedDirectory(data.directory, path)
  if acquired != FileError.None: return fail[StorageDurability](acquired)
  defer:
    if owner.data == nil: discard retire(data) # Failed bootstrap keeps forensic children but releases every lease.
  let checkpoint = createManagedFile(data.directory, ManagedFileKind.Snapshot, ManagedEpoch(1),
      image.encodedBytes, config.snapshot.bytes)
  if checkpoint != FileError.None: return fail[StorageDurability](checkpoint)
  let created = createManagedFile(data.directory, ManagedFileKind.Journal, ManagedEpoch(1),
      anchor.value, config.journal.bytes)
  if created != FileError.None: return fail[StorageDurability](created)
  let journal = openManagedJournal(data.journal, data.directory, ManagedEpoch(1),
      config.journal.bytes)
  if journal.error != FileError.None: return fail[StorageDurability](journal.error)
  let published = replaceManagedManifest(data.directory, selected.value.bytes, ByteLimit(LightJournalManifestBytes))
  if published != FileError.None: return fail[StorageDurability](published)
  data.selected = selected.value
  data.image = image
  data.sequence = LightDeltaSequence(0)
  owner.data = data
  LightJournalResult[StorageDurability](status: FileError.None,
      completed: StorageDurability.FileAndDirectorySynced)
proc preparedSnapshot*(owner: LightJournalCache): LightJournalResult[PreparedLightSnapshot] =
  ## Retain the confirmed proof image without a native lease or a new durability claim.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[PreparedLightSnapshot](reason)
  assert data != nil
  LightJournalResult[PreparedLightSnapshot](status: FileError.None, completed: data.image)
proc snapshot*(owner: LightJournalCache): LightJournalResult[LightStateCache] =
  ## Return an immutable read-only proof cache only while current ownership is confirmed.
  let selected = owner.preparedSnapshot
  if selected.error != FileError.None: return fail[LightStateCache](selected.error)
  LightJournalResult[LightStateCache](status: FileError.None, completed: selected.value.cache)
proc sequence*(owner: LightJournalCache): LightJournalResult[LightDeltaSequence] =
  ## Fresh scalar metadata refuses when the durable selection is uncertain.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[LightDeltaSequence](reason)
  assert data != nil
  LightJournalResult[LightDeltaSequence](status: FileError.None, completed: data.sequence)
proc epoch*(owner: LightJournalCache): LightJournalResult[ManagedEpoch] =
  ## Physical selection is independent of local proof-update sequence.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[ManagedEpoch](reason)
  assert data != nil
  LightJournalResult[ManagedEpoch](status: FileError.None, completed: data.selected.epoch)
proc journalBytes*(owner: LightJournalCache): LightJournalResult[uint64] =
  ## Read confirmed append extent without reloading the journal or exporting its descriptor.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[uint64](reason)
  assert data != nil
  let observed = managedJournalBytes(data.journal)
  if observed.error != FileError.None: return fail[uint64](observed.error)
  LightJournalResult[uint64](status: FileError.None, completed: observed.value)
proc append*(owner: var LightJournalCache, delta: PreparedLightDelta): LightJournalResult[
    StorageDurability] =
  ## Bound an opaque authenticated frame to the exact confirmed predecessor/policy, append and synchronize before publication.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[StorageDurability](reason)
  assert data != nil
  if not delta.initialized: return fail[StorageDurability](FileError.Uninitialized)
  if data.frames >= uint64(data.config.journal.frames) or uint64(data.sequence) == high(
      uint64): return fail[StorageDurability](FileError.LimitExceeded)
  let checked = binding(delta.snapshot, data.config)
  if checked != FileError.None: return fail[StorageDurability](checked)
  if uint64(delta.sequence) != uint64(data.sequence)+1 or
      array[32, byte](delta.baseChecksum) != array[32, byte](data.image.checksum): return fail[
          StorageDurability](FileError.StaleView)
  let extent = lightDeltaExtent(delta.encodedBytes, data.config.journal.frame)
  if extent.error != LightDeltaError.None: return fail[StorageDurability](deltaReason(extent.error))
  if extent.value != delta.byteLength: return fail[StorageDurability](FileError.InvalidFrame)
  let appended = appendManagedJournal(data.journal, delta.encodedBytes)
  if appended != FileError.None:
    # Only uncertainty poisons; ordinary capacity refusal occurs before physical append and permits another bounded edit.
    if appended in {FileError.IoFailure, FileError.PublishedUnsynced,
        FileError.RecoveryRequired}: data.poisoned = true
    return fail[StorageDurability](appended)
  data.image = delta.snapshot
  data.sequence = delta.sequence
  inc data.frames
  LightJournalResult[StorageDurability](status: FileError.None,
      completed: StorageDurability.FileAndDirectorySynced)
proc update*(owner: var LightJournalCache, proofs: openArray[LightStateProof],
    forgotten: openArray[StateKey]): LightJournalResult[StorageDurability] =
  ## Prepare one complete proof batch privately, then reuse the exact same sparse durable append publication path.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[StorageDurability](reason)
  assert data != nil
  if data.frames >= uint64(data.config.journal.frames) or uint64(data.sequence) == high(
      uint64): return fail[StorageDurability](FileError.LimitExceeded)
  let prepared = prepareLightDelta(data.image, LightDeltaSequence(uint64(data.sequence)+1), proofs,
      forgotten, data.config.journal.frame)
  let checked = deltaReason(prepared.error)
  if checked != FileError.None: return fail[StorageDurability](checked)
  owner.append(prepared.value)

type
  RecoveryOwner = ref object ## Explicit partial-tail inspection retains exactly the lease/inode whose bytes authorized its plan.
    owner: JournalOwner
    plan: LightTailPlan
  LightJournalRecovery* = object ## Move-only repair/retirement authority is distinct from a fresh writable journal owner.
    data: nil RecoveryOwner
proc `=copy`*(destination: var LightJournalRecovery, source: LightJournalRecovery) {.error.}
  ## A repair lease has one native retirement authority.
proc `=dup`*(source: LightJournalRecovery): LightJournalRecovery {.error.}
  ## Reject hidden duplication of a recovery handle during actual lowering.
proc requireClosed(recovery: LightJournalRecovery) {.requires: recovery.data == nil.} =
  ## A caller must explicitly repair-transfer or close every held inspection.
  discard
proc `=destroy`*(recovery: LightJournalRecovery) =
  ## Moved-from recovery values are inert; live native inspection cannot silently retire in destruction.
  requireClosed(recovery)
  `=destroy`(recovery.data)
func opened*(recovery: LightJournalRecovery): bool =
  ## Default and transferred recovery handles safely report an absent lease.
  recovery.data != nil
proc close*(recovery: var LightJournalRecovery): FileError =
  ## Retire append before directory and disarm the inspection even if native close fails.
  let data = recovery.data
  if data == nil: return FileError.Uninitialized
  let reason = retire(data.owner)
  recovery.data = nil
  reason
proc plan*(recovery: LightJournalRecovery): LightJournalResult[LightTailPlan] =
  ## Retain only a checked immutable prefix plan; it grants no fresh writable owner or durability receipt.
  let data = recovery.data
  if data == nil: return fail[LightTailPlan](FileError.Uninitialized)
  let reason = lifecycle(data.owner)
  if reason != FileError.None: return fail[LightTailPlan](reason)
  LightJournalResult[LightTailPlan](status: FileError.None, completed: data.plan)
proc inspectLightJournalTail*(recovery: var LightJournalRecovery, path: string,
    config: LightJournalConfig): FileError =
  ## Hold the selected directory and journal inode while explicitly planning only a bounded structurally possible incomplete suffix.
  if recovery.opened: return FileError.Busy
  var data = JournalOwner(config: config)
  let acquired = openManagedDirectory(data.directory, path)
  if acquired != FileError.None: return acquired
  defer:
    if recovery.data == nil: discard retire(data) # Failed inspection exposes no held authority and preserves forensic bytes.
  let selected = readSelection(data)
  if selected.error != FileError.None: return selected.error
  data.selected = selected.value
  var loaded = readManagedFile(data.directory, ManagedFileKind.Snapshot, data.selected.epoch,
      config.snapshot.bytes)
  if loaded.error != FileError.None: return loaded.error
  var encoded = loaded.takeValue
  let checkpoint = takeLightSnapshot(encoded, config.chain, config.root, config.snapshot)
  let reason = snapshotReason(checkpoint.error)
  if reason != FileError.None: return reason
  var journal = openManagedJournal(data.journal, data.directory, data.selected.epoch,
      config.journal.bytes)
  if journal.error != FileError.None: return journal.error
  var input = journal.takeValue
  let planned = planLightJournalTail(input, data.selected, checkpoint.value, config.journal)
  if planned.error != LightReplayError.None:
    # Complete corruption never becomes salvage; only an explicit nonempty incomplete next frame can authorize inspection.
    case planned.error
    of LightReplayError.LimitExceeded, LightReplayError.SequenceExhausted: return FileError.LimitExceeded
    of LightReplayError.BackendFailure: return FileError.BackendFailure
    of LightReplayError.InvalidSelection: return selectionReason(planned.selectionError)
    of LightReplayError.InvalidDelta: return deltaReason(planned.deltaError)
    of LightReplayError.WrongCheckpoint: return FileError.WrongIdentity
    else: return FileError.InvalidJournal
  recovery.data = RecoveryOwner(owner: data, plan: planned.value)
  FileError.None
proc revalidateCheckpoint(data: JournalOwner): FileError =
  ## Explicit destructive repair also rechecks the selected checkpoint bytes against the same trusted manifest before truncation.
  var loaded = readManagedFile(data.directory, ManagedFileKind.Snapshot, data.selected.epoch,
      data.config.snapshot.bytes)
  if loaded.error != FileError.None: return loaded.error
  var encoded = loaded.takeValue
  let restored = takeLightSnapshot(encoded, data.config.chain, data.config.root,
      data.config.snapshot)
  let reason = snapshotReason(restored.error)
  if reason != FileError.None: return reason
  if array[32, byte](restored.value.checksum) != array[32, byte](data.selected.snapshotChecksum):
    return FileError.RecoveryMismatch
  FileError.None
proc repair*(recovery: var LightJournalRecovery, owner: var LightJournalCache): LightJournalResult[
    StorageDurability] =
  ## Revalidate current selection, held inode/extent and all original bytes, then truncate/sync exactly the authenticated prefix before transfer.
  if owner.opened: return fail[StorageDurability](FileError.Busy)
  let data = recovery.data
  if data == nil: return fail[StorageDurability](FileError.Uninitialized)
  let reason = lifecycle(data.owner)
  if reason != FileError.None: return fail[StorageDurability](reason)
  let selected = readSelection(data.owner)
  if selected.error != FileError.None:
    data.owner.poisoned = true
    return fail[StorageDurability](selected.error)
  if array[32, byte](selected.value.checksum) != array[32, byte](data.plan.selectionChecksum):
    data.owner.poisoned = true
    return fail[StorageDurability](FileError.RecoveryMismatch)
  let checkpoint = revalidateCheckpoint(data.owner)
  if checkpoint != FileError.None:
    data.owner.poisoned = true
    return fail[StorageDurability](checkpoint)
  var loaded = readHeldManagedJournal(data.owner.journal, data.owner.directory,
      data.owner.selected.epoch)
  if loaded.error != FileError.None:
    data.owner.poisoned = true
    return fail[StorageDurability](loaded.error)
  var bytes = loaded.takeValue
  let checked = validateLightTailPlan(bytes, selected.value, data.plan)
  if checked != LightReplayError.None:
    data.owner.poisoned = true
    return fail[StorageDurability](if checked == LightReplayError.BackendFailure: FileError.BackendFailure else: FileError.RecoveryMismatch)
  let retained = data.plan.prefix
  let truncated = truncateManagedJournal(data.owner.journal, uint64(retained.byteLength))
  if truncated != FileError.None:
    # Both pre-truncate uncertainty and failed post-truncate durability require close and fresh strict reopen/inspection.
    data.owner.poisoned = true
    return fail[StorageDurability](truncated)
  data.owner.image = retained.snapshot
  data.owner.sequence = retained.sequence
  data.owner.frames = retained.frameCount
  owner.data = data.owner
  recovery.data = nil
  LightJournalResult[StorageDurability](status: FileError.None,
      completed: StorageDurability.FileAndDirectorySynced)

type
  CompactionData = ref object ## Prepared replacement retains immutable evidence and fixed transport, never a native lease or predecessor chain.
    image: PreparedLightSnapshot
    selected: LightJournalManifest
    anchor: seq[byte]
    prior: StorageChecksum
    priorEpoch: ManagedEpoch
    sequence: LightDeltaSequence
  PreparedLightCompaction* = object ## Opaque canonical candidate binds physical replacement to one exact confirmed epoch/sequence/image.
    data: nil CompactionData
  LightCompactionReceipt* = object ## Passive copied diagnostics are never accepted as storage publication authority.
    previousEpoch*: ManagedEpoch ## Old files remain unselected forensic/reclamation candidates after confirmed selection.
    epoch*: ManagedEpoch          ## The new checkpoint epoch is selected and its namespace barriers completed.
    sequence*: LightDeltaSequence ## Compaction preserves the global proof-update sequence.
    retirement*: FileError ## Old-handle retirement is separate from confirmed selection; non-None requires explicit close/reopen.
func initialized*(prepared: PreparedLightCompaction): bool =
  ## Default plans safely report that they carry no candidate authority.
  prepared.data != nil
proc epoch*(prepared: PreparedLightCompaction): ManagedEpoch {.requires: prepared.data != nil.} =
  ## Inspect the exact checked next physical epoch without exporting mutable plan backing.
  let data = prepared.data
  assert data != nil
  data.selected.epoch
proc sequence*(prepared: PreparedLightCompaction): LightDeltaSequence {.requires: prepared.data != nil.} =
  ## Inspect the unchanged checkpoint baseline bound to this candidate.
  let data = prepared.data
  assert data != nil
  data.sequence
proc prepareLightCompaction*(owner: LightJournalCache, expectedEpoch: ManagedEpoch,
    expectedSequence: LightDeltaSequence): LightJournalResult[PreparedLightCompaction] =
  ## Prepare exact checkpoint selection and anchor before IO, checking stale position and epoch exhaustion before arithmetic or hashes.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[PreparedLightCompaction](reason)
  assert data != nil
  if uint64(expectedEpoch) != uint64(data.selected.epoch) or
      uint64(expectedSequence) != uint64(data.sequence): return fail[PreparedLightCompaction](
          FileError.StaleView)
  if uint64(data.selected.epoch) == high(uint64): return fail[PreparedLightCompaction](
      FileError.EpochExhausted)
  let next = ManagedEpoch(uint64(data.selected.epoch)+1)
  let selected = prepareLightJournalManifest(data.image, next, data.sequence, ByteLimit(LightJournalManifestBytes))
  if selected.error != LightSelectionError.None: return fail[PreparedLightCompaction](
      selectionReason(selected.error))
  let anchor = encodeLightJournalAnchor(selected.value, data.config.journal.bytes)
  if anchor.error != LightSelectionError.None: return fail[PreparedLightCompaction](selectionReason(anchor.error))
  LightJournalResult[PreparedLightCompaction](status: FileError.None,
    completed: PreparedLightCompaction(data: CompactionData(image: data.image,
      selected: selected.value,
      anchor: anchor.value, prior: data.selected.checksum, priorEpoch: data.selected.epoch,
      sequence: data.sequence)))
proc compact*(owner: var LightJournalCache, prepared: PreparedLightCompaction): LightJournalResult[
    LightCompactionReceipt] =
  ## Write/sync a new checkpoint and empty journal, atomically select them, then separately report retirement of the old append handle.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[LightCompactionReceipt](reason)
  assert data != nil
  let plan = prepared.data
  if plan == nil: return fail[LightCompactionReceipt](FileError.Uninitialized)
  let checked = binding(plan.image, data.config)
  if checked != FileError.None: return fail[LightCompactionReceipt](checked)
  if uint64(data.selected.epoch) != uint64(plan.priorEpoch) or
      uint64(data.sequence) != uint64(plan.sequence) or
      array[32, byte](data.selected.checksum) != array[32, byte](plan.prior) or
      array[32, byte](data.image.checksum) != array[32, byte](plan.image.checksum):
    return fail[LightCompactionReceipt](FileError.StaleView)
  if uint64(plan.anchor.len) > uint64(data.config.journal.bytes): return fail[
      LightCompactionReceipt](FileError.LimitExceeded)
  var journal = default(ManagedJournal)
  defer:
    if journal.opened: discard journal.close # Refused staging always releases its candidate inode before the selected owner's lease retires.
  var staged = createManagedFile(data.directory, ManagedFileKind.Snapshot, plan.selected.epoch,
    plan.image.encodedBytes, data.config.snapshot.bytes)
  if staged == FileError.None:
    staged = createManagedFile(data.directory, ManagedFileKind.Journal, plan.selected.epoch,
        plan.anchor, data.config.journal.bytes)
  if staged != FileError.None:
    # Existing candidate names cause no selected-file uncertainty; other IO refusals require strict reopen.
    if staged != FileError.AlreadyExists: data.poisoned = true
    return fail[LightCompactionReceipt](staged)
  var loaded = openManagedJournal(journal, data.directory, plan.selected.epoch,
      data.config.journal.bytes)
  if loaded.error != FileError.None:
    data.poisoned = true
    return fail[LightCompactionReceipt](loaded.error)
  var input = loaded.takeValue
  if input != plan.anchor:
    data.poisoned = true
    return fail[LightCompactionReceipt](FileError.InvalidJournal)
  let selected = replaceManagedManifest(data.directory, plan.selected.bytes, ByteLimit(LightJournalManifestBytes))
  if selected != FileError.None:
    # Post-rename uncertainty never grants confirmed epoch or compaction receipt; the old reader is retained only by prior callers.
    data.poisoned = true
    return fail[LightCompactionReceipt](selected)
  let prior = data.selected.epoch
  let closed = data.journal.close
  let moved = moveManagedJournal(data.journal, journal)
  data.selected = plan.selected
  data.frames = 0
  let retirement = if closed != FileError.None: closed else: moved
  if retirement != FileError.None: data.poisoned = true
  LightJournalResult[LightCompactionReceipt](status: FileError.None,
    completed: LightCompactionReceipt(previousEpoch: prior, epoch: plan.selected.epoch,
      sequence: data.sequence, retirement: retirement))
