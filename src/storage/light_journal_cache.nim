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
func sameJournalPolicy(left, right: LightReplayLimits): bool =
  ## A prepared root request cannot silently adopt different replay/append capacities after close/reopen.
  uint64(left.bytes) == uint64(right.bytes) and uint64(left.frames) == uint64(right.frames) and
    uint64(left.frame.bytes) == uint64(right.frame.bytes) and uint64(left.frame.items) == uint64(
        right.frame.items)
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
proc readStreamedJournal(data: JournalOwner): FileError =
  ## Retire checkpoint extraction aliases before advancing frame-sized replay; publish only after final EOF revalidation.
  var progress = default(LightJournalReplay)
  var total = 0'u64
  block:
    # Only progress retains the checked checkpoint after this scope; a first successor can release it before later replay.
    var loaded = readManagedFile(data.directory, ManagedFileKind.Snapshot, data.selected.epoch,
        data.config.snapshot.bytes)
    if loaded.error != FileError.None: return loaded.error
    var encoded = loaded.takeValue
    let restored = takeLightSnapshot(encoded, data.config.chain, data.config.root,
        data.config.snapshot)
    let checked = snapshotReason(restored.error)
    if checked != FileError.None: return checked
    let attached = attachManagedJournal(data.journal, data.directory, data.selected.epoch,
        data.config.journal.bytes)
    if attached != FileError.None: return attached
    total = managedJournalBytes(data.journal).value
    var anchor = default(array[LightJournalAnchorBytes, byte])
    let readAnchor = readManagedJournalRange(data.journal, data.directory, data.selected.epoch, 0, anchor)
    if readAnchor.error != FileError.None: return readAnchor.error
    let started = beginLightJournalReplay(anchor.toOpenArray(0, readAnchor.value-1), data.selected,
        restored.value, data.config.journal)
    let reason = replayReason(started)
    if reason != FileError.None: return reason
    progress = started.value
  while uint64(progress.byteLength) < total:
    # Bound work and sequence before reading a header or allocating its declared extent.
    if progress.frameCount >= uint64(data.config.journal.frames) or uint64(progress.sequence) ==
        high(uint64):
      return FileError.LimitExceeded
    let offset = uint64(progress.byteLength)
    var header = default(array[LightDeltaHeaderBytes, byte])
    let readHeader = readManagedJournalRange(data.journal, data.directory, data.selected.epoch,
        offset, header)
    if readHeader.error != FileError.None: return readHeader.error
    if readHeader.value < LightDeltaHeaderBytes:
      return replayReason(advanceLightJournalReplay(progress, header.toOpenArray(0,
          readHeader.value-1), data.config.journal))
    let checkedHeader = advanceLightJournalReplay(progress, header, data.config.journal)
    if checkedHeader.error != LightReplayError.IncompleteTail: return replayReason(checkedHeader)
    let declared = lightDeltaDeclaredExtent(header, data.config.journal.frame)
    if declared.error != LightDeltaError.None: return deltaReason(declared.error)
    let available = int(min(uint64(declared.value), total-offset))
    var frame = newSeq[byte](available)
    for index in 0..<LightDeltaHeaderBytes: frame[index] = header[index]
    let body = readManagedJournalRange(data.journal, data.directory, data.selected.epoch,
      offset+uint64(LightDeltaHeaderBytes), frame.toOpenArray(LightDeltaHeaderBytes, frame.len-1))
    if body.error != FileError.None: return body.error
    if body.value != frame.len-LightDeltaHeaderBytes: return FileError.RecoveryMismatch
    let advanced = advanceLightJournalReplay(progress, frame, data.config.journal)
    let checked = replayReason(advanced)
    if checked != FileError.None: return checked
    progress = advanced.value
  var endWindow = default(array[0, byte])
  let finished = readManagedJournalRange(data.journal, data.directory, data.selected.epoch, total, endWindow)
  if finished.error != FileError.None: return finished.error
  data.image = progress.snapshot
  data.sequence = progress.sequence
  data.frames = progress.frameCount
  FileError.None
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
  let replayed = readStreamedJournal(data)
  if replayed != FileError.None: return replayed
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
  LightJournalEdit* = object ## Borrowed synchronous batch input contains one ordinary disjoint proof-cache update.
    proofs*: seq[LightStateProof] ## Incoming independently verified evidence obeys the existing per-frame proof/cache limits.
    forgotten*: seq[StateKey] ## Explicit local-evidence removal never invents authenticated absence.
  BatchData = ref object ## Prepared transport retains only the final immutable image and exact predecessor position, not every intermediate image.
    image: PreparedLightSnapshot
    encoded: seq[byte]
    selected, prior: StorageChecksum
    epoch: ManagedEpoch
    before, last: LightDeltaSequence
    frames, priorFrames, priorBytes: uint64
    policy: LightReplayLimits
  PreparedLightJournalBatch* = object ## Opaque prepared concatenation grants no durable publication receipt until its append barrier succeeds.
    data: nil BatchData
func initialized*(batch: PreparedLightJournalBatch): bool =
  ## Default batches have no encoded-frame or successor authority.
  batch.data != nil
proc frameCount*(batch: PreparedLightJournalBatch): uint64 {.requires: batch.data != nil.} =
  ## Report the exact nonempty number of authenticated consecutive update frames.
  let data = batch.data
  assert data != nil
  data.frames
proc byteLength*(batch: PreparedLightJournalBatch): int {.requires: batch.data != nil.} =
  ## Report completed canonical transport extent without exporting mutable bytes.
  let data = batch.data
  assert data != nil
  data.encoded.len
proc sequence*(batch: PreparedLightJournalBatch): LightDeltaSequence {.requires: batch.data != nil.} =
  ## Inspect the checked final global sequence, independent of physical epoch.
  let data = batch.data
  assert data != nil
  data.last
proc snapshot*(batch: PreparedLightJournalBatch): PreparedLightSnapshot {.requires: batch.data != nil.} =
  ## Retain only the prepared immutable final candidate; it is not a durable-head receipt.
  let data = batch.data
  assert data != nil
  data.image
proc prepareLightJournalBatch*(owner: LightJournalCache,
    edits: openArray[LightJournalEdit]): LightJournalResult[PreparedLightJournalBatch] =
  ## Authenticate consecutive updates privately within all inherited caps, retaining only final image and bounded aggregate frame bytes.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[PreparedLightJournalBatch](reason)
  assert data != nil
  if edits.len == 0: return fail[PreparedLightJournalBatch](FileError.InvalidBatch)
  let count = uint64(edits.len)
  let maximumFrames = uint64(data.config.journal.frames)
  if data.frames > maximumFrames or count > maximumFrames-data.frames or
      count > high(uint64)-uint64(data.sequence): return fail[PreparedLightJournalBatch](
          FileError.LimitExceeded)
  let observed = managedJournalBytes(data.journal)
  if observed.error != FileError.None: return fail[PreparedLightJournalBatch](observed.error)
  let maximum = min(uint64(data.config.journal.bytes), uint64(high(int)))
  if observed.value > maximum or count > (maximum-observed.value) div uint64(LightDeltaOverhead):
    return fail[PreparedLightJournalBatch](FileError.LimitExceeded)
  let capacity = maximum-observed.value
  var encoded = newSeq[byte](0)
  var current = data.image
  var sequence = data.sequence
  for edit in edits:
    # Remaining aggregate bytes constrain each frame before its own shape allocation and proof/backend work.
    var limits = data.config.journal.frame
    limits.bytes = ByteLimit(min(uint64(limits.bytes), capacity-uint64(encoded.len)))
    if uint64(sequence) == high(uint64): return fail[PreparedLightJournalBatch](
        FileError.LimitExceeded)
    let next = prepareLightDelta(current, LightDeltaSequence(uint64(sequence)+1), edit.proofs,
        edit.forgotten, limits)
    if next.error != LightDeltaError.None: return fail[PreparedLightJournalBatch](deltaReason(next.error))
    let prepared = next.value
    for octet in prepared.encodedBytes: encoded.add(octet)
    current = prepared.snapshot
    sequence = prepared.sequence
  LightJournalResult[PreparedLightJournalBatch](status: FileError.None,
    completed: PreparedLightJournalBatch(data: BatchData(image: current, encoded: move(encoded),
      selected: data.selected.checksum, prior: data.image.checksum, epoch: data.selected.epoch,
      before: data.sequence, last: sequence, frames: count, priorFrames: data.frames,
      priorBytes: observed.value, policy: data.config.journal)))
proc append*(owner: var LightJournalCache, batch: PreparedLightJournalBatch): LightJournalResult[
    StorageDurability] =
  ## Append a prepared consecutive group once and synchronize once before publishing its final image; uncertainty requires explicit prefix recovery.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[StorageDurability](reason)
  assert data != nil
  let prepared = batch.data
  if prepared == nil: return fail[StorageDurability](FileError.Uninitialized)
  if not sameJournalPolicy(prepared.policy, data.config.journal):
    return fail[StorageDurability](FileError.InvalidBatch)
  let bound = binding(prepared.image, data.config)
  if bound != FileError.None: return fail[StorageDurability](bound)
  let observed = managedJournalBytes(data.journal)
  if observed.error != FileError.None: return fail[StorageDurability](observed.error)
  if uint64(prepared.epoch) != uint64(data.selected.epoch) or
      uint64(prepared.before) != uint64(data.sequence) or prepared.priorFrames != data.frames or
      prepared.priorBytes != observed.value or
      array[32, byte](prepared.selected) != array[32, byte](data.selected.checksum) or
      array[32, byte](prepared.prior) != array[32, byte](data.image.checksum):
    return fail[StorageDurability](FileError.StaleView)
  let maximumFrames = uint64(data.config.journal.frames)
  let maximum = min(uint64(data.config.journal.bytes), uint64(high(int)))
  if data.frames > maximumFrames or prepared.frames > maximumFrames-data.frames or
      observed.value > maximum or uint64(prepared.encoded.len) > maximum-observed.value:
    return fail[StorageDurability](FileError.LimitExceeded)
  let written = appendManagedJournal(data.journal, prepared.encoded)
  if written != FileError.None:
    # A complete prefix may already exist; neither automatic rollback nor an all-or-nothing disk claim is permitted.
    data.poisoned = true
    return fail[StorageDurability](written)
  data.image = prepared.image
  data.sequence = prepared.last
  data.frames += prepared.frames
  LightJournalResult[StorageDurability](status: FileError.None,
      completed: StorageDurability.FileAndDirectorySynced)

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
proc readCheckedCheckpoint(data: JournalOwner): LightJournalResult[PreparedLightSnapshot] =
  ## Destructive operations recheck the selected checkpoint bytes, proof policy and exact trusted manifest checksum.
  var loaded = readManagedFile(data.directory, ManagedFileKind.Snapshot, data.selected.epoch,
      data.config.snapshot.bytes)
  if loaded.error != FileError.None: return fail[PreparedLightSnapshot](loaded.error)
  var encoded = loaded.takeValue
  let restored = takeLightSnapshot(encoded, data.config.chain, data.config.root,
      data.config.snapshot)
  let reason = snapshotReason(restored.error)
  if reason != FileError.None: return fail[PreparedLightSnapshot](reason)
  if array[32, byte](restored.value.checksum) != array[32, byte](data.selected.snapshotChecksum):
    return fail[PreparedLightSnapshot](FileError.RecoveryMismatch)
  LightJournalResult[PreparedLightSnapshot](status: FileError.None, completed: restored.value)
proc revalidateCheckpoint(data: JournalOwner): FileError =
  ## Repair needs the same strict checkpoint admission without retaining an additional image after this check.
  readCheckedCheckpoint(data).error
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

proc validateSelectedHead(data: JournalOwner): FileError =
  ## Before namespace deletion reauthenticate exact CURRENT, checkpoint and actual held journal against the owner's confirmed head.
  let selected = readSelection(data)
  if selected.error != FileError.None: return selected.error
  if array[32, byte](selected.value.checksum) != array[32, byte](
      data.selected.checksum): return FileError.RecoveryMismatch
  let checkpoint = readCheckedCheckpoint(data)
  if checkpoint.error != FileError.None: return checkpoint.error
  var loaded = readHeldManagedJournal(data.journal, data.directory, data.selected.epoch)
  if loaded.error != FileError.None: return loaded.error
  var input = loaded.takeValue
  let replayed = replayLightJournal(input, selected.value, checkpoint.value, data.config.journal)
  let reason = replayReason(replayed)
  if reason != FileError.None: return reason
  if uint64(replayed.value.sequence) != uint64(data.sequence) or
      replayed.value.frameCount != data.frames or
      array[32, byte](replayed.value.snapshot.checksum) != array[32, byte](data.image.checksum):
    return FileError.RecoveryMismatch
  FileError.None
proc cleanupRetiredEpoch*(owner: var LightJournalCache, epoch: ManagedEpoch): FileError =
  ## Explicitly remove only an earlier canonical pair after selected-head revalidation; retries synchronize even already absent names.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return reason
  assert data != nil
  if uint64(epoch) == 0 or uint64(epoch) >= uint64(
      data.selected.epoch): return FileError.InvalidRetention
  let checked = validateSelectedHead(data)
  if checked != FileError.None:
    data.poisoned = true
    return checked
  let journal = removeManagedFile(data.directory, ManagedFileKind.Journal, epoch)
  if journal != FileError.None: return journal
  let checkpoint = removeManagedFile(data.directory, ManagedFileKind.Snapshot, epoch)
  if checkpoint != FileError.None: return checkpoint
  data.directory.synchronize # A prior last-unlink barrier failure cannot become a false durable success merely because both names are now absent.
proc discardPending*(owner: var LightJournalCache): FileError =
  ## Explicitly discard only fixed unselected CURRENT.next after exact selected-head revalidation, never adopting its payload.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return reason
  assert data != nil
  let checked = validateSelectedHead(data)
  if checked != FileError.None:
    data.poisoned = true
    return checked
  let removed = discardManagedPending(data.directory)
  if removed != FileError.None: return removed
  data.directory.synchronize
proc discardUnselectedCompaction*(owner: var LightJournalCache,
    prepared: PreparedLightCompaction): FileError =
  ## Remove only the prepared immediate unselected epoch and matching partial staging after preflighting every possible candidate prefix.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return reason
  assert data != nil
  let plan = prepared.data
  if plan == nil: return FileError.Uninitialized
  if uint64(data.selected.epoch) == high(uint64): return FileError.EpochExhausted
  if uint64(plan.selected.epoch) <= uint64(data.selected.epoch): return FileError.InvalidRetention
  if uint64(plan.priorEpoch) != uint64(data.selected.epoch) or
      uint64(plan.selected.epoch) != uint64(data.selected.epoch)+1 or
      uint64(plan.sequence) > uint64(data.sequence) or
      array[32, byte](plan.prior) != array[32, byte](
          data.selected.checksum): return FileError.StaleView
  let bound = binding(plan.image, data.config)
  if bound != FileError.None: return bound
  let checked = validateSelectedHead(data)
  if checked != FileError.None:
    data.poisoned = true
    return checked
  var candidate = validateManagedFilePrefix(data.directory, ManagedFileKind.Snapshot,
    plan.selected.epoch, plan.image.encodedBytes, data.config.snapshot.bytes)
  if candidate == FileError.None:
    candidate = validateManagedFilePrefix(data.directory, ManagedFileKind.Journal,
      plan.selected.epoch, plan.anchor, data.config.journal.bytes)
  if candidate == FileError.None:
    candidate = validateManagedPendingPrefix(data.directory, plan.selected.bytes, ByteLimit(LightJournalManifestBytes))
  if candidate != FileError.None: return candidate # Unknown or malformed candidate content preserves all files and confirmed selected authority.
  let pending = discardManagedPending(data.directory)
  if pending != FileError.None: return pending
  let journal = removeManagedFile(data.directory, ManagedFileKind.Journal, plan.selected.epoch)
  if journal != FileError.None: return journal
  let checkpoint = removeManagedFile(data.directory, ManagedFileKind.Snapshot, plan.selected.epoch)
  if checkpoint != FileError.None: return checkpoint
  data.directory.synchronize

type
  RootAdvanceData = ref object ## Immutable target and exact source policy/position carry no native lease or predecessor image chain.
    image: PreparedLightSnapshot
    selected: LightJournalManifest
    anchor: seq[byte]
    source: LightJournalConfig
    prior, priorImage: StorageChecksum
    priorEpoch: ManagedEpoch
    sequence: LightDeltaSequence
    frames, bytes: uint64
  PreparedLightRootAdvance* = object ## Opaque root selection authenticates replacement evidence without supplying root provenance.
    data: nil RootAdvanceData
  LightRootAdvanceReceipt* = object ## Passive confirmed selection and retirement diagnostics never grant new root trust or publication authority.
    previousRoot*, root*: StateRoot ## Both roots were independently selected by the caller, not inferred from transport.
    previousEpoch*, epoch*: ManagedEpoch ## Retired source files remain until explicit guarded reclamation.
    sequence*: LightDeltaSequence ## Root selection preserves the ordinary proof-update sequence.
    retirement*: FileError ## Non-None preserves confirmed selection but poisons fresh owner access until explicit retirement/reopen.
func initialized*(prepared: PreparedLightRootAdvance): bool =
  ## Default plans safely report that they carry no publication candidate.
  prepared.data != nil
proc epoch*(prepared: PreparedLightRootAdvance): ManagedEpoch {.requires: prepared.data != nil.} =
  ## Inspect only the exact checked destination physical epoch.
  let data = prepared.data
  assert data != nil
  data.selected.epoch
proc sequence*(prepared: PreparedLightRootAdvance): LightDeltaSequence {.requires: prepared.data != nil.} =
  ## The new checkpoint baseline preserves the source's confirmed ordinary-update sequence.
  let data = prepared.data
  assert data != nil
  data.sequence
proc root*(prepared: PreparedLightRootAdvance): StateRoot {.requires: prepared.data != nil.} =
  ## Return the explicit independently accepted destination root without granting provenance.
  let data = prepared.data
  assert data != nil
  data.image.root
proc snapshot*(prepared: PreparedLightRootAdvance): PreparedLightSnapshot {.requires: prepared.data != nil.} =
  ## Retain only the immutable verified replacement knowledge, independently of any native owner.
  let data = prepared.data
  assert data != nil
  data.image
proc rootAdvanceSource(data: JournalOwner, plan: RootAdvanceData, cleanup: bool): FileError =
  ## Exact publication requires the original head; cleanup may tolerate only later ordinary appends in that same physical selection.
  if uint64(data.selected.epoch) != uint64(plan.priorEpoch) or
      array[32, byte](data.selected.checksum) != array[32, byte](plan.prior) or
      array[32, byte](data.config.chain) != array[32, byte](plan.source.chain) or
      array[32, byte](data.config.root) != array[32, byte](
          plan.source.root): return FileError.StaleView
  if not samePolicy(data.config.snapshot, plan.source.snapshot) or
      not sameJournalPolicy(data.config.journal, plan.source.journal): return FileError.InvalidBatch
  let extent = managedJournalBytes(data.journal)
  if extent.error != FileError.None: return extent.error
  if cleanup:
    # Append position is monotonic within one unchanged selected manifest; no later physical selection is admitted above.
    if uint64(data.sequence) < uint64(plan.sequence) or data.frames < plan.frames or extent.value < plan.bytes:
      return FileError.StaleView
  else:
    let sameImage = array[32, byte](data.image.checksum) == array[32, byte](plan.priorImage)
    if uint64(data.sequence) != uint64(plan.sequence) or data.frames != plan.frames or
        extent.value != plan.bytes or not sameImage: return FileError.StaleView
  FileError.None
proc prepareLightRootAdvance*(owner: LightJournalCache, expectedEpoch: ManagedEpoch,
    expectedSequence: LightDeltaSequence, destinationRoot: StateRoot,
    image: PreparedLightSnapshot): LightJournalResult[PreparedLightRootAdvance] =
  ## Bind separately verified destination knowledge to an explicit root argument and one exact confirmed source, without IO.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[PreparedLightRootAdvance](reason)
  assert data != nil
  if uint64(expectedEpoch) != uint64(data.selected.epoch) or uint64(expectedSequence) != uint64(data.sequence):
    return fail[PreparedLightRootAdvance](FileError.StaleView)
  if uint64(data.selected.epoch) == high(uint64): return fail[PreparedLightRootAdvance](
      FileError.EpochExhausted)
  if not image.initialized: return fail[PreparedLightRootAdvance](FileError.Uninitialized)
  if array[32, byte](image.chainId) != array[32, byte](data.config.chain) or
      array[32, byte](image.root) != array[32, byte](destinationRoot):
    return fail[PreparedLightRootAdvance](FileError.WrongIdentity)
  if array[32, byte](destinationRoot) == array[32, byte](data.config.root) or
      not samePolicy(image.limits, data.config.snapshot): return fail[PreparedLightRootAdvance](
          FileError.InvalidBatch)
  let extent = managedJournalBytes(data.journal)
  if extent.error != FileError.None: return fail[PreparedLightRootAdvance](extent.error)
  let selected = prepareLightJournalManifest(image, ManagedEpoch(uint64(data.selected.epoch)+1),
      data.sequence,
    ByteLimit(LightJournalManifestBytes))
  if selected.error != LightSelectionError.None: return fail[PreparedLightRootAdvance](
      selectionReason(selected.error))
  let anchor = encodeLightJournalAnchor(selected.value, data.config.journal.bytes)
  if anchor.error != LightSelectionError.None: return fail[PreparedLightRootAdvance](
      selectionReason(anchor.error))
  LightJournalResult[PreparedLightRootAdvance](status: FileError.None,
    completed: PreparedLightRootAdvance(data: RootAdvanceData(image: image,
      selected: selected.value,
      anchor: anchor.value, source: data.config, prior: data.selected.checksum,
      priorImage: data.image.checksum,
      priorEpoch: data.selected.epoch, sequence: data.sequence, frames: data.frames,
      bytes: extent.value)))
proc advanceRoot*(owner: var LightJournalCache, prepared: PreparedLightRootAdvance): LightJournalResult[
    LightRootAdvanceReceipt] =
  ## Synchronize replacement evidence/anchor before selecting the new root; only confirmed selection changes the owner's root binding.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[LightRootAdvanceReceipt](reason)
  assert data != nil
  let plan = prepared.data
  if plan == nil: return fail[LightRootAdvanceReceipt](FileError.Uninitialized)
  let checked = rootAdvanceSource(data, plan, false)
  if checked != FileError.None: return fail[LightRootAdvanceReceipt](checked)
  var journal = default(ManagedJournal)
  defer:
    if journal.opened: discard journal.close # An unselected candidate never retains a native lease after a refused publication.
  var staged = createManagedFile(data.directory, ManagedFileKind.Snapshot, plan.selected.epoch,
    plan.image.encodedBytes, data.config.snapshot.bytes)
  if staged == FileError.None:
    staged = createManagedFile(data.directory, ManagedFileKind.Journal, plan.selected.epoch,
      plan.anchor,
      data.config.journal.bytes)
  if staged != FileError.None:
    # Existing unselected children are preserved; other partial IO makes fresh observations uncertain.
    if staged != FileError.AlreadyExists: data.poisoned = true
    return fail[LightRootAdvanceReceipt](staged)
  var loaded = openManagedJournal(journal, data.directory, plan.selected.epoch,
      data.config.journal.bytes)
  if loaded.error != FileError.None:
    data.poisoned = true
    return fail[LightRootAdvanceReceipt](loaded.error)
  var input = loaded.takeValue
  if input != plan.anchor:
    data.poisoned = true
    return fail[LightRootAdvanceReceipt](FileError.InvalidJournal)
  let selected = replaceManagedManifest(data.directory, plan.selected.bytes, ByteLimit(LightJournalManifestBytes))
  if selected != FileError.None:
    # CURRENT may have changed after rename; no source/destination root is selected from forensic bytes on this path.
    data.poisoned = true
    return fail[LightRootAdvanceReceipt](selected)
  let priorEpoch = data.selected.epoch
  let priorRoot = data.config.root
  let closed = data.journal.close
  let moved = moveManagedJournal(data.journal, journal)
  data.selected = plan.selected
  data.image = plan.image
  data.config.root = plan.image.root
  data.frames = 0
  let retirement = if closed != FileError.None: closed else: moved
  if retirement != FileError.None: data.poisoned = true
  LightJournalResult[LightRootAdvanceReceipt](status: FileError.None,
    completed: LightRootAdvanceReceipt(previousRoot: priorRoot, root: plan.image.root,
      previousEpoch: priorEpoch,
      epoch: plan.selected.epoch, sequence: data.sequence, retirement: retirement))
proc discardUnselectedRootAdvance*(owner: var LightJournalCache,
    prepared: PreparedLightRootAdvance): FileError =
  ## Validate the selected source and all candidate prefixes before deleting only this plan's immediate unselected epoch.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return reason
  assert data != nil
  let plan = prepared.data
  if plan == nil: return FileError.Uninitialized
  if uint64(plan.selected.epoch) <= uint64(data.selected.epoch): return FileError.InvalidRetention
  if uint64(data.selected.epoch) == high(uint64): return FileError.EpochExhausted
  if uint64(plan.selected.epoch) != uint64(data.selected.epoch)+1: return FileError.StaleView
  let source = rootAdvanceSource(data, plan, true)
  if source != FileError.None: return source
  let checked = validateSelectedHead(data)
  if checked != FileError.None:
    data.poisoned = true
    return checked
  var candidate = validateManagedFilePrefix(data.directory, ManagedFileKind.Snapshot,
    plan.selected.epoch,
    plan.image.encodedBytes, data.config.snapshot.bytes)
  if candidate == FileError.None:
    candidate = validateManagedFilePrefix(data.directory, ManagedFileKind.Journal,
      plan.selected.epoch,
      plan.anchor, data.config.journal.bytes)
  if candidate == FileError.None:
    candidate = validateManagedPendingPrefix(data.directory, plan.selected.bytes, ByteLimit(LightJournalManifestBytes))
  if candidate != FileError.None: return candidate # Unknown unselected content preserves every candidate and the confirmed source.
  let pending = discardManagedPending(data.directory)
  if pending != FileError.None: return pending
  let journal = removeManagedFile(data.directory, ManagedFileKind.Journal, plan.selected.epoch)
  if journal != FileError.None: return journal
  let checkpoint = removeManagedFile(data.directory, ManagedFileKind.Snapshot, plan.selected.epoch)
  if checkpoint != FileError.None: return checkpoint
  data.directory.synchronize

proc prepareLightRetainedUpdate*(owner: LightJournalCache, proofs: openArray[LightStateProof],
    limits: LightRetentionLimits): LightJournalResult[PreparedLightJournalBatch] =
  ## Choose bounded quota eviction privately, then authenticate one ordinary frame bound to this exact physical source and policy.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[PreparedLightJournalBatch](reason)
  assert data != nil
  if data.frames >= uint64(data.config.journal.frames) or uint64(data.sequence) == high(uint64):
    return fail[PreparedLightJournalBatch](FileError.LimitExceeded)
  let observed = managedJournalBytes(data.journal)
  if observed.error != FileError.None: return fail[PreparedLightJournalBatch](observed.error)
  let maximum = min(uint64(data.config.journal.bytes), uint64(high(int)))
  if observed.value > maximum or uint64(LightDeltaOverhead) > maximum-observed.value:
    return fail[PreparedLightJournalBatch](FileError.LimitExceeded)
  let planned = planLightRetention(data.image, proofs, limits)
  if planned.error == LightSnapshotError.ProofFailure:
    return fail[PreparedLightJournalBatch](FileError.InvalidBatch)
  if planned.error != LightSnapshotError.None:
    return fail[PreparedLightJournalBatch](snapshotReason(planned.error))
  var frame = data.config.journal.frame
  frame.bytes = ByteLimit(min(uint64(frame.bytes), maximum-observed.value))
  let prepared = prepareLightDelta(data.image, LightDeltaSequence(uint64(data.sequence)+1), proofs,
    planned.value.forgottenKeys, frame)
  if prepared.error != LightDeltaError.None:
    return fail[PreparedLightJournalBatch](deltaReason(prepared.error))
  let delta = prepared.value
  LightJournalResult[PreparedLightJournalBatch](status: FileError.None,
    completed: PreparedLightJournalBatch(data: BatchData(image: delta.snapshot,
      encoded: delta.bytes,
      selected: data.selected.checksum, prior: data.image.checksum, epoch: data.selected.epoch,
      before: data.sequence, last: delta.sequence, frames: 1, priorFrames: data.frames,
      priorBytes: observed.value, policy: data.config.journal)))
proc admitRetained*(owner: var LightJournalCache, proofs: openArray[LightStateProof],
    limits: LightRetentionLimits): LightJournalResult[StorageDurability] =
  ## Publish admission and chosen evictions in one synchronized append; uncertainty requires existing explicit strict reopen or tail repair.
  let prepared = prepareLightRetainedUpdate(owner, proofs, limits)
  if prepared.error != FileError.None: return fail[StorageDurability](prepared.error)
  owner.append(prepared.value)

type
  LightMaintenanceLimits* = object ## Explicit opt-in compaction thresholds and one bounded canonical retired-epoch sweep.
    frames*: ElementLimit ## Zero disables this trigger; nonzero counts ordinary frames since the selected checkpoint.
    bytes*: ByteLimit ## Zero disables this trigger; charge only journal frame bytes, excluding the fixed anchor.
    first*: ManagedEpoch ## Explicit canonical sweep cursor; disabled sweeps ignore it and expose zero.
    epochs*, keep*: ElementLimit ## Bound retirement jobs and preserve this many earlier physical epochs behind the selected head.
  MaintenanceData = ref object ## Immutable preparation retains metadata plus at most one existing compaction image, never a native lease.
    source: LightJournalConfig
    selected, image: StorageChecksum
    epoch: ManagedEpoch
    sequence: LightDeltaSequence
    frames, bytes, retired: uint64
    first: ManagedEpoch
    compaction: PreparedLightCompaction
  PreparedLightMaintenance* = object ## Exact source-bound policy decisions authorize only existing guarded compaction and canonical retirement APIs.
    data: nil MaintenanceData
  LightMaintenanceReceipt* = object ## Passive confirmed head plus partial synchronized retirement progress is never root trust or retry authority.
    previousEpoch*, epoch*: ManagedEpoch
    sequence*: LightDeltaSequence
    compacted*: bool
    retired*: ElementLimit ## Completed canonical pair jobs, including synchronized already-absent retries.
    nextRetiredEpoch*: ManagedEpoch ## First unfinished requested job, or the exclusive end after complete retirement.
    retirement*, cleanup*: FileError ## Confirmed compaction retirement and later cleanup errors remain distinct from publication refusal.
func initialized*(prepared: PreparedLightMaintenance): bool =
  ## Default plans safely report their missing source binding.
  prepared.data != nil
proc compactionNeeded*(prepared: PreparedLightMaintenance): bool {.requires: prepared.data != nil.} =
  ## Inspect a completed threshold decision without granting an independent compaction candidate.
  let data = prepared.data
  assert data != nil
  data.compaction.initialized
proc retiredCount*(prepared: PreparedLightMaintenance): ElementLimit {.requires: prepared.data != nil.} =
  ## Inspect the exact bounded number of canonical pair jobs, without scanning any directory.
  let data = prepared.data
  assert data != nil
  ElementLimit(data.retired)
proc firstRetiredEpoch*(prepared: PreparedLightMaintenance): ManagedEpoch {.requires: prepared.data != nil.} =
  ## Inspect the explicit sweep cursor; a disabled sweep may retain zero.
  let data = prepared.data
  assert data != nil
  data.first
proc prepareLightMaintenance*(owner: LightJournalCache, expectedEpoch: ManagedEpoch,
    expectedSequence: LightDeltaSequence, limits: LightMaintenanceLimits): LightJournalResult[
        PreparedLightMaintenance] =
  ## Decide work from one confirmed source, preserving image/root/sequence and all exact policies; preparation performs no IO.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[PreparedLightMaintenance](reason)
  assert data != nil
  if uint64(data.selected.epoch) != uint64(expectedEpoch) or uint64(data.sequence) != uint64(expectedSequence):
    return fail[PreparedLightMaintenance](FileError.StaleView)
  let observed = managedJournalBytes(data.journal)
  if observed.error != FileError.None: return fail[PreparedLightMaintenance](observed.error)
  assert observed.value >= uint64(LightJournalAnchorBytes)
  let capacity = uint64(data.config.journal.bytes)
  assert capacity >= uint64(LightJournalAnchorBytes)
  if uint64(limits.frames) > uint64(data.config.journal.frames) or
      uint64(limits.bytes) > capacity-uint64(LightJournalAnchorBytes):
    return fail[PreparedLightMaintenance](FileError.LimitExceeded)
  let frameTrigger = uint64(limits.frames) > 0 and data.frames >= uint64(limits.frames)
  let byteTrigger = uint64(limits.bytes) > 0 and observed.value-uint64(LightJournalAnchorBytes) >=
      uint64(limits.bytes)
  let compact = data.frames > 0 and (frameTrigger or byteTrigger)
  var target = uint64(data.selected.epoch)
  if compact:
    # The prospective physical epoch must be representable before any manifest hashing or retirement-range arithmetic.
    if target == high(uint64): return fail[PreparedLightMaintenance](FileError.EpochExhausted)
    inc target
  let first = if uint64(limits.epochs) == 0: 0'u64 else: uint64(limits.first)
  var count = 0'u64
  if uint64(limits.epochs) > 0:
    # Retired canonical slots are strictly below the prospective selected head; no arbitrary future namespace is admitted.
    if first == 0 or first > target: return fail[PreparedLightMaintenance](
        FileError.InvalidRetention)
    if uint64(limits.keep) < target-1:
      let last = target-1-uint64(limits.keep)
      if first <= last: count = min(uint64(limits.epochs), last-first+1)
  var compaction = default(PreparedLightCompaction)
  if compact:
    # Reuse the ordinary immutable compaction candidate and its explicit abandoned-candidate cleanup authority.
    let prepared = prepareLightCompaction(owner, expectedEpoch, expectedSequence)
    if prepared.error != FileError.None: return fail[PreparedLightMaintenance](prepared.error)
    compaction = prepared.value
  LightJournalResult[PreparedLightMaintenance](status: FileError.None,
    completed: PreparedLightMaintenance(data: MaintenanceData(source: data.config,
      selected: data.selected.checksum, image: data.image.checksum, epoch: data.selected.epoch,
      sequence: data.sequence, frames: data.frames, bytes: observed.value, first: ManagedEpoch(
          first),
      retired: count, compaction: compaction)))
proc maintenanceSource(data: JournalOwner, plan: MaintenanceData): FileError =
  ## Any physical/image/ordinary-update/policy change stales a prepared sweep, including same-root return cycles.
  if not samePolicy(data.config.snapshot, plan.source.snapshot) or
      not sameJournalPolicy(data.config.journal, plan.source.journal): return FileError.InvalidBatch
  let sameChain = array[32, byte](data.config.chain) == array[32, byte](plan.source.chain)
  let sameRoot = array[32, byte](data.config.root) == array[32, byte](plan.source.root)
  let sameSelection = array[32, byte](data.selected.checksum) == array[32, byte](plan.selected)
  let sameImage = array[32, byte](data.image.checksum) == array[32, byte](plan.image)
  let sameEpoch = uint64(data.selected.epoch) == uint64(plan.epoch)
  let sameSequence = uint64(data.sequence) == uint64(plan.sequence)
  if not sameEpoch or not sameSequence or data.frames != plan.frames: return FileError.StaleView
  if not sameChain or not sameRoot or not sameSelection or not sameImage: return FileError.StaleView
  let observed = managedJournalBytes(data.journal)
  if observed.error != FileError.None: return observed.error
  if observed.value != plan.bytes: return FileError.StaleView
  FileError.None
proc maintain*(owner: var LightJournalCache, prepared: PreparedLightMaintenance): LightJournalResult[
    LightMaintenanceReceipt] =
  ## Confirm optional compaction before bounded retired-pair jobs; later cleanup failures return exact progress at the confirmed head.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return fail[LightMaintenanceReceipt](reason)
  assert data != nil
  let plan = prepared.data
  if plan == nil: return fail[LightMaintenanceReceipt](FileError.Uninitialized)
  let checked = maintenanceSource(data, plan)
  if checked != FileError.None: return fail[LightMaintenanceReceipt](checked)
  var receipt = LightMaintenanceReceipt(previousEpoch: data.selected.epoch,
    epoch: data.selected.epoch,
    sequence: data.sequence, compacted: false, retired: ElementLimit(0),
    nextRetiredEpoch: plan.first, retirement: FileError.None,
    cleanup: FileError.None)
  if plan.compaction.initialized:
    # Before confirmed CURRENT selection, ordinary publication failures expose no successful maintenance receipt.
    let compacted = owner.compact(plan.compaction)
    if compacted.error != FileError.None: return fail[LightMaintenanceReceipt](compacted.error)
    receipt.compacted = true
    receipt.epoch = compacted.value.epoch
    receipt.retirement = compacted.value.retirement
    if receipt.retirement != FileError.None:
      if plan.retired > 0: receipt.cleanup = FileError.RecoveryRequired
      return LightJournalResult[LightMaintenanceReceipt](status: FileError.None, completed: receipt)
  var completed = 0'u64
  var cursor = uint64(plan.first)
  while completed < plan.retired:
    # Each existing guarded pair job revalidates the selected head and synchronizes absence before progress advances.
    let removed = owner.cleanupRetiredEpoch(ManagedEpoch(cursor))
    if removed != FileError.None:
      receipt.cleanup = removed
      return LightJournalResult[LightMaintenanceReceipt](status: FileError.None, completed: receipt)
    inc completed
    assert cursor < uint64(data.selected.epoch)
    inc cursor
    receipt.retired = ElementLimit(completed)
    receipt.nextRetiredEpoch = ManagedEpoch(cursor)
  LightJournalResult[LightMaintenanceReceipt](status: FileError.None, completed: receipt)
proc discardUnselectedMaintenance*(owner: var LightJournalCache,
    prepared: PreparedLightMaintenance): FileError =
  ## Explicitly discard only a matching unselected maintenance compaction; source appends retain the existing cleanup-only tolerance.
  let data = owner.data
  let reason = lifecycle(data)
  if reason != FileError.None: return reason
  let plan = prepared.data
  if plan == nil: return FileError.Uninitialized
  if not plan.compaction.initialized: return FileError.InvalidBatch
  owner.discardUnselectedCompaction(plan.compaction)
