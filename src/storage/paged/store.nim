# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Storage-only durable paged-light owners: exclusive writers, sealed candidates and independent pinned readers.
## Complete stream verification precedes selection. Explicit close and passive post-confirmation diagnostics preserve uncertainty.
import std/assertions
import ./[io as paged_io, codec as paged_codec, stream as paged_stream]
import ../managed/manifest as managed_manifest
import ../light/delta as light_delta
import ../database_identity
import ../file/errors as file_errors
import ../[durability, state_proof]
import ../../codec/bounded
import ../../codec/state/[layout as state_layout, trie as state_trie]

type
  PagedNativeError* {.pure.} = enum ## Failed/default operations carry no fresh head, reader or successful publication prefix.
    Uninitialized, None, FileFailure, StreamFailure, UnknownKey, RecoveryRequired, StaleView,
    CounterExhausted, InvalidCandidate, InvalidTransition
  PagedNativeResult*[T] = object ## Only selected failure alternatives expose their specific cause.
    case status: PagedNativeError
    of None: completed: T
    of FileFailure: fileCause: FileError
    of StreamFailure:
      streamCause: PagedStreamError
      proofCause: StateProofError
    else: discard
  PagedNativeConfig* = object ## Independently selected chain/root and exact inherited policies never come from disk.
    chain*: StorageChainId
    root*: StateRoot
    limits*: PagedStreamLimits
  PagedBuildKind {.pure.} = enum ## Ordinary replacement advances sequence; root advance and compaction preserve it.
    Replacement, Advance, Compaction
  WriterData = ref object ## Stable private writer incarnation binds candidate preparation without descriptor-number ABA.
    directory: PagedDirectory
    head: PagedFile
    active, poisoned, selected: bool
    config: PagedNativeConfig
    checked: CheckedPagedArtifact
  PagedWriter* = object ## Sole writer-lease/selected-handle retirement authority; it owns no retained reader.
    data: nil WriterData
  CandidateData = ref object ## A candidate retains the original writer incarnation but never prolongs its native lease after close.
    file, pending: PagedFile
    owner: WriterData
    source: PagedManifest
    checked: CheckedPagedArtifact
    active, sealed, initial, recovery: bool
  PagedCandidate* = object ## Unique authoring/sealed artifact owner; failed authoring must still be explicitly closed.
    data: nil CandidateData
  ReaderData = ref object ## One independent pinned immutable epoch and captured policies survive writer publication/close.
    file: PagedFile
    config: PagedNativeConfig
    checked: CheckedPagedArtifact
    active, poisoned: bool
  PagedReader* = object ## Move-only explicit-close native reader, never an alias of its writer's selected descriptor.
    data: nil ReaderData
  PagedPublication* = object ## Confirmed durable selection is independent of later native-handle retirement diagnostics.
    ready: bool
    selected: PagedManifest
    retirement: FileError
    usable: bool
  PagedEpochReceipt* = object ## Captured checked epoch/inode/policy authority owns no pin; the source reader may subsequently close.
    ready: bool
    selected: PagedManifest
    identity: PagedFileIdentity
    config: PagedNativeConfig
  PagedReclamation* = object ## Confirmed durable absence remains successful even when post-unlink handle retirement reports failure.
    ready: bool
    absentBefore: bool
    retirement: FileError

func opened*(writer: PagedWriter): bool =
  ## Default/moved/closed owners hold no writer retirement authority.
  let data = writer.data
  data != nil and data.active
func opened*(candidate: PagedCandidate): bool =
  ## Failed authoring may still own a forensic file descriptor that requires explicit close.
  let data = candidate.data
  data != nil and data.active
func opened*(reader: PagedReader): bool =
  ## Retained reader lifetime is independent of CURRENT and the writer lease.
  let data = reader.data
  data != nil and data.active
proc `=copy`*(destination: var PagedWriter, source: PagedWriter) {.error.}
  ## Composite ownership has one close authority even though its private implementation is ref-backed.
proc `=dup`*(source: PagedWriter): PagedWriter {.error.}
  ## Actual native lowering must reject hidden owner duplication.
proc `=copy`*(destination: var PagedCandidate, source: PagedCandidate) {.error.}
  ## Copying may not duplicate sealed-artifact or authoring close authority.
proc `=dup`*(source: PagedCandidate): PagedCandidate {.error.}
  ## Prepared metadata never revives a closed or copied native artifact.
proc `=copy`*(destination: var PagedReader, source: PagedReader) {.error.}
  ## Independent readers require independent opens and pins.
proc `=dup`*(source: PagedReader): PagedReader {.error.}
  ## A copied immutable view must not duplicate native retirement authority.
proc closed(writer: PagedWriter) {.requires: not writer.opened.} =
  ## Native close uncertainty remains observable instead of being hidden by a destructor.
  discard
proc closed(candidate: PagedCandidate) {.requires: not candidate.opened.} =
  ## Both unsuccessful authoring and sealed candidates require explicit retirement.
  discard
proc closed(reader: PagedReader) {.requires: not reader.opened.} =
  ## A retained native pin cannot silently outlive its last exported owner.
  discard
proc `=wasMoved`*(writer: var PagedWriter) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(writer.data)

proc `=destroy`*(writer: PagedWriter) =
  ## Default/moved values pass; live leases require explicit close.
  closed(writer)
  `=destroy`(writer.data)
proc `=wasMoved`*(candidate: var PagedCandidate) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(candidate.data)

proc `=destroy`*(candidate: PagedCandidate) =
  ## Explicit close preserves forensic files and reports native retirement failure.
  closed(candidate)
  `=destroy`(candidate.data)
proc `=wasMoved`*(reader: var PagedReader) {.nodestroy, inline.} =
  ## Disarm transferred fields through their own move hooks; never destroy the destination resources.
  `=wasMoved`(reader.data)

proc `=destroy`*(reader: PagedReader) =
  ## Owned verified lookups have independent lifetime; the native reader pin must retire explicitly.
  closed(reader)
  `=destroy`(reader.data)
func error*[T](outcome: PagedNativeResult[T]): PagedNativeError =
  ## Inspect only the selected typed outer refusal.
  outcome.status
func value*[T](outcome: PagedNativeResult[T]): T {.inline, requires: outcome.status ==
    PagedNativeError.None.} =
  ## Only complete success grants a position, verified lookup or confirmed receipt.
  outcome.completed
func fileError*[T](outcome: PagedNativeResult[T]): FileError {.requires: outcome.status ==
    PagedNativeError.FileFailure.} =
  ## Preserve only the selected native cause, including Busy and publication uncertainty.
  outcome.fileCause
func streamError*[T](outcome: PagedNativeResult[T]): PagedStreamError {.requires: outcome.status ==
    PagedNativeError.StreamFailure.} =
  ## Preserve only a selected complete-admission/proof/resource refusal.
  outcome.streamCause
func proofError*[T](outcome: PagedNativeResult[T]): StateProofError {.requires:
    outcome.status == PagedNativeError.StreamFailure and outcome.streamCause ==
    PagedStreamError.ProofFailure.} =
  ## A non-proof refusal never exposes an inactive proof cause.
  outcome.proofCause
func fileFailed[T](reason: FileError): PagedNativeResult[T] =
  ## Native refusals contain no completed result or fallback selection.
  PagedNativeResult[T](status: PagedNativeError.FileFailure, fileCause: reason)
func refused[T](reason: PagedNativeError): PagedNativeResult[T] =
  ## Generic refusals do not initialize any success or selected-cause payload.
  PagedNativeResult[T](status: reason)
func streamFailed[T, U](outcome: PagedStreamResult[U]): PagedNativeResult[T] =
  ## UnknownKey is a checked local miss; all other selected stream causes retain their original meaning.
  if outcome.error == PagedStreamError.UnknownKey: return refused[T](PagedNativeError.UnknownKey)
  let proof = if outcome.error == PagedStreamError.ProofFailure: outcome.proofError else: StateProofError.Uninitialized
  PagedNativeResult[T](status: PagedNativeError.StreamFailure, streamCause: outcome.error,
      proofCause: proof)
func manifest*(receipt: PagedPublication): PagedManifest {.requires: receipt.ready.} =
  ## Report the confirmed synchronized selection even when later retirement was imperfect.
  receipt.selected
func retirementError*(receipt: PagedPublication): FileError {.requires: receipt.ready.} =
  ## Post-confirmation failure does not erase the already durable head.
  receipt.retirement
func writerUsable*(receipt: PagedPublication): bool {.requires: receipt.ready.} =
  ## A false value requires explicit close/reopen although the receipt's selection remains confirmed.
  receipt.usable
func durability*(receipt: PagedPublication): StorageDurability {.requires: receipt.ready.} =
  ## Successful publication includes both file and directory barriers.
  StorageDurability.FileAndDirectorySynced
func retirementError*(receipt: PagedReclamation): FileError {.requires: receipt.ready.} =
  ## Already confirmed unlink/directory sync remains successful after descriptor retirement failure.
  receipt.retirement
func alreadyAbsent*(receipt: PagedReclamation): bool {.requires: receipt.ready.} =
  ## Synchronized idempotent absence is distinct from deleting a captured old inode now.
  receipt.absentBefore
func durability*(receipt: PagedReclamation): StorageDurability {.requires: receipt.ready.} =
  ## Absent-name retries also perform a real final directory barrier.
  StorageDurability.FileAndDirectorySynced
proc close*(reader: var PagedReader): FileError =
  ## Poison does not prevent retirement; handles are marked retired before native close and never retried.
  let data = reader.data
  if data == nil or not data.active: return FileError.Uninitialized
  data.active = false
  reader.data = nil
  if data.file.opened: data.file.close else: FileError.None
proc close*(candidate: var PagedCandidate): FileError =
  ## Closing never unlinks an unselected, incomplete or even fully sealed forensic candidate.
  let data = candidate.data
  if data == nil or not data.active: return FileError.Uninitialized
  data.active = false
  candidate.data = nil
  var reason = FileError.None
  if data.file.opened: reason = data.file.close
  if data.pending.opened:
    let retired = data.pending.close
    if reason == FileError.None: reason = retired
  reason
proc close*(writer: var PagedWriter): FileError =
  ## Independent reader/candidate descriptors do not retain this writer's lease or selected handle.
  let data = writer.data
  if data == nil or not data.active: return FileError.Uninitialized
  data.active = false
  writer.data = nil
  var reason = FileError.None
  if data.head.opened: reason = data.head.close
  if data.directory.opened:
    let retired = data.directory.close
    if reason == FileError.None: reason = retired
  reason
proc current(data: WriterData): FileError =
  ## A source position is usable only while the held lease, inode and exact selected manifest remain unchanged.
  if not data.active: return FileError.Uninitialized
  if data.poisoned or not data.selected: return FileError.RecoveryRequired
  let directory = data.directory.check
  if directory != FileError.None:
    data.poisoned = true
    return directory
  let selected = data.directory.readCurrent
  if selected.error != FileError.None:
    data.poisoned = true
    return selected.error
  if selected.value != data.checked.manifest.bytes:
    data.poisoned = true
    return FileError.StaleView
  let file = data.head.check
  if file != FileError.None: data.poisoned = true
  file
proc validateHead(data: WriterData): PagedNativeResult[bool] =
  ## Before any publication/reclamation, reverify complete held source bytes/proofs against the captured manifest.
  let checked = current(data)
  if checked != FileError.None: return fileFailed[bool](checked)
  let verified = validateFile(data.head, data.checked.manifest, data.config.limits)
  if verified.error != PagedStreamError.None:
    if data.head.check != FileError.None: data.poisoned = true
    return streamFailed[bool, CheckedPagedArtifact](verified)
  PagedNativeResult[bool](status: PagedNativeError.None, completed: true)
proc selected*(writer: PagedWriter): PagedNativeResult[PagedManifest] =
  ## Return a checked remembered physical/logical position without granting native resource ownership.
  let data = writer.data
  if data == nil or not data.active: return refused[PagedManifest](PagedNativeError.Uninitialized)
  if data.poisoned: return refused[PagedManifest](PagedNativeError.RecoveryRequired)
  let checked = current(data)
  if checked != FileError.None: return fileFailed[PagedManifest](checked)
  PagedNativeResult[PagedManifest](status: PagedNativeError.None, completed: data.checked.manifest)
proc selected*(reader: PagedReader): PagedNativeResult[PagedManifest] =
  ## Retained readers keep their captured epoch/root/sequence across every writer selection and close.
  let data = reader.data
  if data == nil or not data.active: return refused[PagedManifest](PagedNativeError.Uninitialized)
  if data.poisoned: return refused[PagedManifest](PagedNativeError.RecoveryRequired)
  let checked = data.file.check
  if checked != FileError.None:
    data.poisoned = true
    return fileFailed[PagedManifest](checked)
  PagedNativeResult[PagedManifest](status: PagedNativeError.None, completed: data.checked.manifest)
proc openPagedReader*(reader: var PagedReader, path: string,
    config: PagedNativeConfig): PagedNativeResult[bool] =
  ## Read CURRENT, pin its exact epoch, reread CURRENT, then completely verify under independent expectations.
  if reader.opened: return fileFailed[bool](FileError.Busy)
  var directory = default(PagedDirectory)
  defer:
    if directory.opened:
      let retired = directory.close
      if retired != FileError.None: result = fileFailed[bool](retired)
  let acquired = openDirectory(directory, path, false, false)
  if acquired != FileError.None: return fileFailed[bool](acquired)
  let bytes = directory.readCurrent
  if bytes.error != FileError.None: return fileFailed[bool](bytes.error)
  let manifest = decodePagedManifest(bytes.value, config.chain, config.root, config.limits.dataset,
      ByteLimit(PagedManifestBytes), uint64(config.limits.contextBytes) > 0)
  if manifest.error != PagedCodecError.None: return fileFailed[bool](FileError.WrongIdentity)
  var data = ReaderData(config: config)
  defer:
    if reader.data == nil and data.file.opened:
      let retired = data.file.close
      if retired != FileError.None: result = fileFailed[bool](retired)
  let pinned = openEpoch(data.file, directory, manifest.value.epoch, PagedPin.Shared,
      config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[bool](pinned)
  let again = directory.readCurrent
  if again.error != FileError.None: return fileFailed[bool](again.error)
  if again.value != bytes.value: return refused[bool](PagedNativeError.StaleView)
  let checked = validateFile(data.file, manifest.value, config.limits)
  if checked.error != PagedStreamError.None: return streamFailed[bool, CheckedPagedArtifact](checked)
  let retired = directory.close
  if retired != FileError.None: return fileFailed[bool](retired)
  data.checked = checked.value
  data.active = true
  reader.data = data
  PagedNativeResult[bool](status: PagedNativeError.None, completed: true)
proc openPagedWriter*(writer: var PagedWriter, path: string,
    config: PagedNativeConfig): PagedNativeResult[bool] =
  ## Acquire the existing stable writer lease and strictly admit only CURRENT's independently expected root.
  if writer.opened: return fileFailed[bool](FileError.Busy)
  var data = WriterData(config: config)
  defer:
    if writer.data == nil:
      if data.head.opened:
        let retired = data.head.close
        if retired != FileError.None: result = fileFailed[bool](retired)
      if data.directory.opened:
        let retired = data.directory.close
        if retired != FileError.None: result = fileFailed[bool](retired)
  let acquired = openDirectory(data.directory, path, false, true)
  if acquired != FileError.None: return fileFailed[bool](acquired)
  let bytes = data.directory.readCurrent
  if bytes.error != FileError.None: return fileFailed[bool](bytes.error)
  let manifest = decodePagedManifest(bytes.value, config.chain, config.root, config.limits.dataset,
      ByteLimit(PagedManifestBytes), uint64(config.limits.contextBytes) > 0)
  if manifest.error != PagedCodecError.None: return fileFailed[bool](FileError.WrongIdentity)
  let pinned = openEpoch(data.head, data.directory, manifest.value.epoch, PagedPin.Shared,
      config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[bool](pinned)
  let checked = validateFile(data.head, manifest.value, config.limits)
  if checked.error != PagedStreamError.None: return streamFailed[bool, CheckedPagedArtifact](checked)
  let again = data.directory.readCurrent
  if again.error != FileError.None: return fileFailed[bool](again.error)
  if again.value != bytes.value: return refused[bool](PagedNativeError.StaleView)
  data.checked = checked.value
  data.active = true
  data.selected = true
  writer.data = data
  PagedNativeResult[bool](status: PagedNativeError.None, completed: true)
proc lookup*(reader: var PagedReader, query: StateKey, budget: PagedWorkLimits): PagedNativeResult[
    VerifiedStateLookup] =
  ## No cache page or native owner escapes: only independently owned verified lookup bytes may outlive close.
  let data = reader.data
  if data == nil or not data.active: return refused[VerifiedStateLookup](
      PagedNativeError.Uninitialized)
  if data.poisoned: return refused[VerifiedStateLookup](PagedNativeError.RecoveryRequired)
  let checked = lookupFile(data.file, data.checked, query, budget)
  if checked.error != PagedStreamError.None:
    if data.file.check != FileError.None: data.poisoned = true
    return streamFailed[VerifiedStateLookup, PagedLookup](checked)
  PagedNativeResult[VerifiedStateLookup](status: PagedNativeError.None,
      completed: checked.value.verified)
proc prepare(data: WriterData, candidate: var PagedCandidate, producer: nil PagedProducer,
    root: StateRoot, count, payload: uint64, kind: PagedBuildKind,
        initial: bool, context: openArray[byte] = []): PagedNativeResult[StorageDurability] =
  ## Bind a new exclusive authoring owner to one live writer incarnation and exact source position/policies.
  if candidate.opened: return fileFailed[StorageDurability](FileError.Busy)
  if producer == nil and kind != PagedBuildKind.Compaction: return refused[StorageDurability](
      PagedNativeError.Uninitialized)
  if not data.active: return refused[StorageDurability](PagedNativeError.Uninitialized)
  if not initial and data.poisoned: return refused[StorageDurability](
      PagedNativeError.RecoveryRequired)
  var epoch = 1'u64
  var sequence = 0'u64
  var source = default(PagedManifest)
  if not initial:
    source = data.checked.manifest
    if uint64(source.epoch) == high(uint64) or (kind == PagedBuildKind.Replacement and uint64(
        source.sequence) == high(uint64)):
      return refused[StorageDurability](PagedNativeError.CounterExhausted)
    epoch = uint64(source.epoch)+1
    sequence = uint64(source.sequence)
    if kind == PagedBuildKind.Replacement: inc sequence
    let checked = validateHead(data)
    if checked.error != PagedNativeError.None:
      if checked.error == PagedNativeError.FileFailure: return fileFailed[StorageDurability](
          checked.fileError)
      return PagedNativeResult[StorageDurability](status: PagedNativeError.StreamFailure,
        streamCause: checked.streamError, proofCause: (if checked.streamError ==
            PagedStreamError.ProofFailure: checked.proofError else: StateProofError.Uninitialized))
  let contextSize = if kind == PagedBuildKind.Compaction:
    data.checked.header.geometry.contextBytes # Compaction retains source context without caller substitution.
  else:
    uint64(context.len) # Replacement and root advancement borrow stable caller context synchronously.
  let contextPolicy = validatePagedContextSize(contextSize, data.config.limits.contextBytes)
  if contextPolicy != PagedStreamError.None:
    return PagedNativeResult[StorageDurability](status: PagedNativeError.StreamFailure,
        streamCause: contextPolicy)
  let header = initPagedHeader(data.config.chain, root, ManagedEpoch(epoch), LightDeltaSequence(
      sequence), count, payload, data.config.limits.dataset, contextSize)
  if header.error != PagedCodecError.None: return fileFailed[StorageDurability](
      FileError.LimitExceeded)
  let empty = data.directory.pendingAbsent
  if empty != FileError.None: return fileFailed[StorageDurability](empty)
  var artifact = CandidateData(owner: data, source: source, initial: initial)
  let created = openEpoch(artifact.file, data.directory, ManagedEpoch(epoch), PagedPin.Create,
      data.config.limits.dataset.bytes)
  if created != FileError.None:
    if artifact.file.opened:
      let retired = artifact.file.close
      if retired != FileError.None: return fileFailed[StorageDurability](retired)
    return fileFailed[StorageDurability](created)
  artifact.active = true
  candidate.data = artifact
  let authoring = if kind == PagedBuildKind.Compaction:
    compactFile(artifact.file, data.head, data.checked, header.value)
  else:
    buildFile(artifact.file, producer, header.value, data.config.limits, context)
  if authoring.error != FileError.None: return fileFailed[StorageDurability](authoring.error)
  let built = authoring.value
  if built.error != PagedStreamError.None: return streamFailed[StorageDurability,
      CheckedPagedArtifact](built)
  let synced = artifact.file.synchronize
  if synced != FileError.None: return fileFailed[StorageDurability](synced)
  let durable = data.directory.synchronize
  if durable != FileError.None: return fileFailed[StorageDurability](durable)
  artifact.checked = built.value
  artifact.sealed = true
  PagedNativeResult[StorageDurability](status: PagedNativeError.None,
      completed: StorageDurability.FileAndDirectorySynced)
proc preparePagedReplacement*(writer: var PagedWriter, candidate: var PagedCandidate,
    producer: nil PagedProducer, count, payload: uint64, context: openArray[byte] = [
        ]): PagedNativeResult[StorageDurability] =
  ## Same-root full replacement advances ordinary sequence once, even for explicitly requested equal evidence.
  let data = writer.data
  if data == nil: return refused[StorageDurability](PagedNativeError.Uninitialized)
  prepare(data, candidate, producer, data.config.root, count, payload, PagedBuildKind.Replacement,
      false, context)
proc preparePagedAdvance*(writer: var PagedWriter, candidate: var PagedCandidate,
    destination: StateRoot, producer: nil PagedProducer, count, payload: uint64, context: openArray[
        byte] = []): PagedNativeResult[StorageDurability] =
  ## Destination trust is explicit; all destination evidence is fresh and ordinary sequence is preserved.
  let data = writer.data
  if data == nil: return refused[StorageDurability](PagedNativeError.Uninitialized)
  if array[32, byte](destination) == array[32, byte](data.config.root): return refused[
      StorageDurability](PagedNativeError.InvalidTransition)
  prepare(data, candidate, producer, destination, count, payload, PagedBuildKind.Advance, false, context)
proc preparePagedCompaction*(writer: var PagedWriter,
    candidate: var PagedCandidate): PagedNativeResult[StorageDurability] =
  ## Exact knowledge comes from the held checked source pin; callers cannot substitute a same-root evidence producer.
  let data = writer.data
  if data == nil or not data.active: return refused[StorageDurability](
      PagedNativeError.Uninitialized)
  if data.poisoned: return refused[StorageDurability](PagedNativeError.RecoveryRequired)
  let shape = data.checked.header.geometry
  prepare(data, candidate, nil, data.config.root, shape.entries, shape.payloadBytes,
    PagedBuildKind.Compaction, false)
proc commitGuard(data: WriterData, artifact: CandidateData): proc(): FileError {.closure.} =
  ## Non-nil stable parameters preserve capture provenance across the staged-publication callback.
  proc beforeRename(): FileError {.closure.} =
    ## Recheck source selection and both inode bindings after staging barriers, immediately before atomic rename.
    let source = if artifact.initial: data.directory.initialAbsent else: current(data)
    if source != FileError.None: return source
    artifact.file.check
  beforeRename
proc publish*(writer: var PagedWriter, candidate: var PagedCandidate): PagedNativeResult[
    PagedPublication] =
  ## Only a live exact-incarnation sealed artifact and fully revalidated source may reach atomic selection.
  let data = writer.data
  let artifact = candidate.data
  if data == nil or artifact == nil: return refused[PagedPublication](
      PagedNativeError.Uninitialized)
  if not data.active or not artifact.active or not artifact.sealed: return refused[
      PagedPublication](PagedNativeError.InvalidCandidate)
  if artifact.owner != data: return refused[PagedPublication](PagedNativeError.StaleView)
  if data.poisoned and not artifact.initial: return refused[PagedPublication](
      PagedNativeError.RecoveryRequired)
  if artifact.initial:
    let absent = data.directory.initialAbsent
    if absent != FileError.None: return fileFailed[PagedPublication](absent)
  else:
    if artifact.source.bytes != data.checked.manifest.bytes: return refused[PagedPublication](
        PagedNativeError.StaleView)
    let source = validateHead(data)
    if source.error != PagedNativeError.None:
      if source.error == PagedNativeError.FileFailure: return fileFailed[PagedPublication](
          source.fileError)
      return PagedNativeResult[PagedPublication](status: PagedNativeError.StreamFailure,
        streamCause: source.streamError, proofCause: (if source.streamError ==
            PagedStreamError.ProofFailure: source.proofError else: StateProofError.Uninitialized))
  if not data.directory.sameDirectory(artifact.file): return refused[PagedPublication](
      PagedNativeError.StaleView)
  let target = validateFile(artifact.file, artifact.checked.manifest, data.config.limits)
  if target.error != PagedStreamError.None: return streamFailed[PagedPublication,
      CheckedPagedArtifact](target)
  let stillSource = if artifact.initial: data.directory.initialAbsent else: current(data)
  if stillSource != FileError.None: return fileFailed[PagedPublication](stillSource)
  let bound = artifact.file.check
  if bound != FileError.None: return fileFailed[PagedPublication](bound)
  let published = replaceCurrent(data.directory, artifact.checked.manifest.bytes, commitGuard(data, artifact))
  if published != FileError.None:
    if published != FileError.AlreadyExists: data.poisoned = true
    return fileFailed[PagedPublication](published)
  # Confirmation is irreversible: later retirement/reopen diagnostics cannot erase this synchronized selection.
  data.checked = artifact.checked
  data.config.root = artifact.checked.header.root
  data.selected = true
  data.poisoned = false
  var retirement = candidate.close
  if data.head.opened:
    let retired = data.head.close
    if retirement == FileError.None: retirement = retired
  let adopted = openEpoch(data.head, data.directory, data.checked.manifest.epoch, PagedPin.Shared,
      data.config.limits.dataset.bytes)
  if adopted != FileError.None:
    data.poisoned = true
    if retirement == FileError.None: retirement = adopted
  if retirement != FileError.None: data.poisoned = true
  PagedNativeResult[PagedPublication](status: PagedNativeError.None,
    completed: PagedPublication(ready: true, selected: data.checked.manifest,
      retirement: retirement, usable: not data.poisoned))
proc initializePagedWriter*(writer: var PagedWriter, path: string, config: PagedNativeConfig,
    producer: nil PagedProducer, count, payload: uint64, context: openArray[byte] = [
        ]): PagedNativeResult[PagedPublication] =
  ## Exclusive bootstrap starts at epoch one/sequence zero; acquired failed namespaces require explicit writer close.
  if writer.opened: return fileFailed[PagedPublication](FileError.Busy)
  if producer == nil: return refused[PagedPublication](PagedNativeError.Uninitialized)
  let contextPolicy = validatePagedContextSize(uint64(context.len), config.limits.contextBytes)
  if contextPolicy != PagedStreamError.None:
    return PagedNativeResult[PagedPublication](status: PagedNativeError.StreamFailure,
        streamCause: contextPolicy)
  let header = initPagedHeader(config.chain, config.root, ManagedEpoch(1), LightDeltaSequence(0),
      count, payload, config.limits.dataset, uint64(context.len))
  if header.error != PagedCodecError.None: return fileFailed[PagedPublication](
      FileError.LimitExceeded)
  var data = WriterData(config: config, poisoned: true)
  let acquired = openDirectory(data.directory, path, true, true)
  if acquired != FileError.None:
    if data.directory.opened:
      let retired = data.directory.close
      if retired != FileError.None: return fileFailed[PagedPublication](retired)
    return fileFailed[PagedPublication](acquired)
  data.active = true
  writer.data = data
  var candidate = default(PagedCandidate)
  defer:
    if candidate.opened:
      let retired = candidate.close
      if retired != FileError.None: result = fileFailed[PagedPublication](retired)
  let prepared = prepare(data, candidate, producer, config.root, count, payload,
      PagedBuildKind.Replacement, true, context)
  if prepared.error != PagedNativeError.None:
    if prepared.error == PagedNativeError.FileFailure: return fileFailed[PagedPublication](
        prepared.fileError)
    if prepared.error == PagedNativeError.StreamFailure:
      return PagedNativeResult[PagedPublication](status: PagedNativeError.StreamFailure,
        streamCause: prepared.streamError, proofCause: (if prepared.streamError ==
            PagedStreamError.ProofFailure: prepared.proofError else: StateProofError.Uninitialized))
    return refused[PagedPublication](prepared.error)
  writer.publish(candidate)
proc epochReceipt*(reader: PagedReader): PagedNativeResult[PagedEpochReceipt] =
  ## Capture exact checked old-epoch identity while pinned; reclamation still requires a fresh exclusive pin and source position.
  let data = reader.data
  if data == nil or not data.active: return refused[PagedEpochReceipt](
      PagedNativeError.Uninitialized)
  if data.poisoned: return refused[PagedEpochReceipt](PagedNativeError.RecoveryRequired)
  let identity = data.file.fileIdentity
  if identity.error != FileError.None: return fileFailed[PagedEpochReceipt](identity.error)
  PagedNativeResult[PagedEpochReceipt](status: PagedNativeError.None,
    completed: PagedEpochReceipt(ready: true, selected: data.checked.manifest,
      identity: identity.value, config: data.config))
func policy(limits: PagedStreamLimits): array[15, uint64] =
  ## Exact immutable policy binding covers all dataset/proof/cache/work ceilings, including zero allowances.
  [uint64(limits.dataset.entries), uint64(limits.dataset.bytes), uint64(limits.proof.nodes),
    uint64(limits.proof.valueBytes), uint64(limits.workingBytes), uint64(limits.cachePages),
    uint64(limits.work.ioCalls), uint64(limits.work.producerCalls), uint64(limits.work.pageHashes),
    uint64(limits.work.proofs), uint64(limits.work.nodes), uint64(limits.work.readBytes),
    uint64(limits.work.writeBytes), uint64(limits.work.valueBytes), uint64(limits.contextBytes)]
proc reclaimEpoch(writer: var PagedWriter, previous, expected: PagedManifest,
    receipt: PagedEpochReceipt, capturedIdentity: bool): PagedNativeResult[PagedReclamation] =
  ## Exact expected content is mandatory; captured receipts additionally bind the original inode and policy.
  let data = writer.data
  if data == nil or not data.active or not data.selected: return refused[PagedReclamation](
      PagedNativeError.Uninitialized)
  if data.poisoned: return refused[PagedReclamation](PagedNativeError.RecoveryRequired)
  if not previous.initialized or not expected.initialized: return refused[PagedReclamation](
      PagedNativeError.InvalidCandidate)
  if expected.bytes != data.checked.manifest.bytes: return refused[PagedReclamation](
      PagedNativeError.StaleView)
  let decoded = decodePagedManifest(previous.bytes, data.config.chain, previous.root,
    data.config.limits.dataset, ByteLimit(PagedManifestBytes), uint64(
        data.config.limits.contextBytes) > 0)
  if decoded.error != PagedCodecError.None: return fileFailed[PagedReclamation](
      FileError.WrongIdentity) # Even already-absent content must match the explicit chain/schema/caps.
  if uint64(previous.epoch) >= uint64(expected.epoch): return refused[PagedReclamation](
      PagedNativeError.InvalidCandidate) # Current and future epochs cannot be retired.
  if uint64(previous.sequence) > uint64(expected.sequence): return refused[PagedReclamation](
      PagedNativeError.InvalidCandidate) # Root advance and compaction preserve ordinary sequence.
  if capturedIdentity:
    # Original receipt authority retains its stronger namespace, captured inode and exact inherited policy binding.
    if not receipt.ready: return refused[PagedReclamation](PagedNativeError.InvalidCandidate)
    let chain = array[32, byte](receipt.config.chain) == array[32, byte](data.config.chain)
    let limits = policy(receipt.config.limits) == policy(data.config.limits)
    if not chain or not limits or not data.directory.matchesDirectory(receipt.identity):
      return refused[PagedReclamation](PagedNativeError.InvalidCandidate)
  let source = validateHead(data)
  if source.error != PagedNativeError.None:
    if source.error == PagedNativeError.FileFailure: return fileFailed[PagedReclamation](
        source.fileError)
    return PagedNativeResult[PagedReclamation](status: PagedNativeError.StreamFailure,
      streamCause: source.streamError, proofCause: (if source.streamError ==
          PagedStreamError.ProofFailure: source.proofError else: StateProofError.Uninitialized))
  let pending = data.directory.pendingAbsent
  if pending != FileError.None: return fileFailed[PagedReclamation](pending)
  let exists = data.directory.epochExists(previous.epoch)
  if exists.error != FileError.None: return fileFailed[PagedReclamation](exists.error)
  if not exists.value:
    let held = current(data)
    if held != FileError.None: return fileFailed[PagedReclamation](
        held) # Idempotent absence still fences the exact current source.
    let confirmed = data.directory.synchronize
    if confirmed != FileError.None:
      data.poisoned = true
      return fileFailed[PagedReclamation](confirmed)
    return PagedNativeResult[PagedReclamation](status: PagedNativeError.None,
      completed: PagedReclamation(ready: true, absentBefore: true, retirement: FileError.None))
  var file = default(PagedFile)
  defer:
    if file.opened:
      let retired = file.close
      if retired != FileError.None: result = fileFailed[PagedReclamation](retired)
  let pinned = openEpoch(file, data.directory, previous.epoch, PagedPin.Exclusive,
      data.config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[PagedReclamation](pinned)
  if capturedIdentity:
    # Equal bytes in a substituted inode cannot satisfy a previously captured physical receipt.
    let actual = file.fileIdentity
    if actual.error != FileError.None: return fileFailed[PagedReclamation](actual.error)
    if not receipt.identity.matches(actual.value): return fileFailed[PagedReclamation](
        FileError.RecoveryMismatch)
  let verified = validateFile(file, previous, data.config.limits)
  if verified.error != PagedStreamError.None: return streamFailed[PagedReclamation,
      CheckedPagedArtifact](verified)
  let current = current(data)
  if current != FileError.None: return fileFailed[PagedReclamation](current)
  let removed = removePinned(data.directory, file)
  if removed != FileError.None:
    data.poisoned = true
    return fileFailed[PagedReclamation](removed)
  let retired = file.close
  PagedNativeResult[PagedReclamation](status: PagedNativeError.None,
    completed: PagedReclamation(ready: true, absentBefore: false, retirement: retired))

proc reclaim*(writer: var PagedWriter, receipt: PagedEpochReceipt,
    expected: PagedManifest): PagedNativeResult[PagedReclamation] =
  ## Existing captured-inode retirement remains stricter than independently expected content authority after restart.
  reclaimEpoch(writer, receipt.selected, expected, receipt, true)
proc reclaimExpectedEpoch*(writer: var PagedWriter, previous,
    expected: PagedManifest): PagedNativeResult[PagedReclamation] =
  ## Independently authenticated previous metadata identifies exact old content, never a directory-derived cleanup wildcard.
  reclaimEpoch(writer, previous, expected, default(PagedEpochReceipt), false)

proc prepareCleanup(data: WriterData, candidate: var PagedCandidate,
    expectedSource: PagedManifest, expectedTarget: PagedHeader,
    producer: nil PagedProducer, initial: bool, context: openArray[byte] = []): PagedNativeResult[bool] =
  ## Reproduce independently expected target bytes in anonymous bounded scratch before capturing any partial cleanup authority.
  if not data.active: return refused[bool](PagedNativeError.Uninitialized)
  if data.poisoned and not initial: return refused[bool](PagedNativeError.RecoveryRequired)
  if candidate.opened: return fileFailed[bool](FileError.Busy)
  if producer == nil or not expectedTarget.initialized or (not initial and
      not expectedSource.initialized):
    return refused[bool](PagedNativeError.InvalidCandidate)
  var source = default(PagedManifest)
  if initial:
    # A failed bootstrap grants only independently checked CURRENT absence, never a disk-derived source head.
    if data.selected or expectedSource.initialized: return refused[bool](
        PagedNativeError.InvalidCandidate)
    let absent = data.directory.initialAbsent
    if absent != FileError.None: return fileFailed[bool](absent)
    let identity = array[32, byte](expectedTarget.root) == array[32, byte](data.config.root)
    if not identity or uint64(expectedTarget.epoch) != 1 or uint64(expectedTarget.sequence) != 0:
      return refused[bool](PagedNativeError.InvalidTransition)
  else:
    # Existing-database recovery binds exact physical source position before any producer or scratch work.
    source = data.checked.manifest
    if expectedSource.bytes != source.bytes: return refused[bool](PagedNativeError.StaleView)
    if uint64(source.epoch) == high(uint64): return refused[bool](PagedNativeError.CounterExhausted)
    if uint64(expectedTarget.epoch) != uint64(source.epoch)+1:
      return refused[bool](PagedNativeError.InvalidTransition)
  if array[32, byte](expectedTarget.chainId) != array[32, byte](data.config.chain):
    return refused[bool](PagedNativeError.InvalidTransition)
  let shape = expectedTarget.geometry
  let contextPolicy = validatePagedContextSize(uint64(context.len), data.config.limits.contextBytes)
  if contextPolicy != PagedStreamError.None:
    return PagedNativeResult[bool](status: PagedNativeError.StreamFailure,
        streamCause: contextPolicy)
  if uint64(context.len) != shape.contextBytes: return refused[bool](
      PagedNativeError.InvalidCandidate)
  let bounded = pagedGeometry(shape.entries, shape.payloadBytes, data.config.limits.dataset,
      shape.contextBytes)
  if bounded.error != PagedCodecError.None: return fileFailed[bool](FileError.LimitExceeded)
  if shape.byteLength > uint64(data.config.limits.work.writeBytes):
    return PagedNativeResult[bool](status: PagedNativeError.StreamFailure,
        streamCause: PagedStreamError.LimitExceeded)
  let sameRoot = initial or array[32, byte](expectedTarget.root) == array[32, byte](source.root)
  let sameSequence = initial or uint64(expectedTarget.sequence) == uint64(source.sequence)
  if not initial:
    # Root changes preserve ordinary sequence; same-root updates either advance once or reproduce exact compaction knowledge.
    let replacement = uint64(source.sequence) < high(uint64) and
      uint64(expectedTarget.sequence) == uint64(source.sequence)+1
    if (not sameRoot and not sameSequence) or (sameRoot and not sameSequence and not replacement):
      return refused[bool](PagedNativeError.InvalidTransition)
    let head = validateHead(data)
    if head.error != PagedNativeError.None:
      if head.error == PagedNativeError.FileFailure: return fileFailed[bool](head.fileError)
      return PagedNativeResult[bool](status: PagedNativeError.StreamFailure,
        streamCause: head.streamError, proofCause: (if head.streamError ==
            PagedStreamError.ProofFailure: head.proofError else: StateProofError.Uninitialized))
  var scratch = default(PagedFile)
  defer:
    if scratch.opened:
      let retired = scratch.close
      if retired != FileError.None: result = fileFailed[bool](retired)
  let acquired = openScratch(scratch, data.directory, data.config.limits.dataset.bytes)
  if acquired != FileError.None: return fileFailed[bool](acquired)
  let authoring = buildFile(scratch, producer, expectedTarget, data.config.limits, context)
  if authoring.error != FileError.None: return fileFailed[bool](authoring.error)
  let built = authoring.value
  if built.error != PagedStreamError.None: return streamFailed[bool, CheckedPagedArtifact](built)
  if not initial and sameRoot and sameSequence and not samePagedKnowledge(data.checked, built.value):
    return refused[bool](PagedNativeError.InvalidTransition)
  var artifact = CandidateData(owner: data, source: source, checked: built.value, recovery: true,
      initial: initial)
  defer:
    if candidate.data == nil:
      if artifact.file.opened:
        let retired = artifact.file.close
        if retired != FileError.None: result = fileFailed[bool](retired)
      if artifact.pending.opened:
        let retired = artifact.pending.close
        if retired != FileError.None: result = fileFailed[bool](retired)
  let exists = data.directory.epochExists(expectedTarget.epoch)
  if exists.error != FileError.None: return fileFailed[bool](exists.error)
  if exists.value:
    # Existing bytes grant authority only after complete-file-prefix comparison under an independent exclusive pin.
    let pinned = openEpoch(artifact.file, data.directory, expectedTarget.epoch,
      PagedPin.Exclusive, data.config.limits.dataset.bytes)
    if pinned != FileError.None: return fileFailed[bool](pinned)
    let matched = matchesPrefix(artifact.file, scratch, data.config.limits.work)
    if matched != FileError.None: return fileFailed[bool](matched)
  let pending = openPending(artifact.pending, data.directory)
  if pending.error != FileError.None: return fileFailed[bool](pending.error)
  if pending.value:
    # Preflight staging bytes before either namespace child can be unlinked.
    let matched = matchesPrefix(artifact.pending, built.value.manifest.bytes,
        data.config.limits.work)
    if matched != FileError.None: return fileFailed[bool](matched)
  let current = if initial: data.directory.initialAbsent else: current(data)
  if current != FileError.None: return fileFailed[bool](current)
  let retired = scratch.close
  if retired != FileError.None: return fileFailed[bool](retired)
  artifact.active = true
  candidate.data = artifact
  PagedNativeResult[bool](status: PagedNativeError.None, completed: true)
proc preparePagedCleanup*(writer: var PagedWriter, candidate: var PagedCandidate,
    expectedSource: PagedManifest, expectedTarget: PagedHeader,
    producer: nil PagedProducer, context: openArray[byte] = []): PagedNativeResult[bool] =
  ## Existing-database replay requires an exact independently expected source and a fresh target proof producer.
  let data = writer.data
  if data == nil: return refused[bool](PagedNativeError.Uninitialized)
  prepareCleanup(data, candidate, expectedSource, expectedTarget, producer, false, context)
proc discardPagedCandidate*(writer: var PagedWriter, candidate: var PagedCandidate,
    expectedSource: PagedManifest): PagedNativeResult[PagedReclamation] =
  ## Retire one exact sealed or replay-checked partial candidate only after every source/file/staging preflight passes.
  let data = writer.data
  let artifact = candidate.data
  if data == nil or artifact == nil: return refused[PagedReclamation](
      PagedNativeError.Uninitialized)
  if not data.active or not artifact.active:
    return refused[PagedReclamation](PagedNativeError.InvalidCandidate)
  if artifact.owner != data: return refused[PagedReclamation](PagedNativeError.StaleView)
  if artifact.initial and (not artifact.recovery or data.selected):
    return refused[PagedReclamation](PagedNativeError.InvalidCandidate)
  if data.poisoned and not artifact.initial: return refused[PagedReclamation](
      PagedNativeError.RecoveryRequired)
  if artifact.initial:
    # Initial cleanup is valid only in an explicitly unselected bootstrap incarnation.
    if expectedSource.initialized or artifact.source.initialized: return refused[PagedReclamation](
        PagedNativeError.StaleView)
    let absent = data.directory.initialAbsent
    if absent != FileError.None: return fileFailed[PagedReclamation](absent)
  else:
    # Passive expected positions cannot revive a stale candidate or silently follow CURRENT.
    if not expectedSource.initialized or expectedSource.bytes != artifact.source.bytes or
        expectedSource.bytes != data.checked.manifest.bytes:
      return refused[PagedReclamation](PagedNativeError.StaleView)
    let head = validateHead(data)
    if head.error != PagedNativeError.None:
      if head.error == PagedNativeError.FileFailure: return fileFailed[PagedReclamation](head.fileError)
      return PagedNativeResult[PagedReclamation](status: PagedNativeError.StreamFailure,
        streamCause: head.streamError, proofCause: (if head.streamError ==
            PagedStreamError.ProofFailure: head.proofError else: StateProofError.Uninitialized))
  if not artifact.sealed and not artifact.recovery:
    return refused[PagedReclamation](PagedNativeError.InvalidCandidate)
  let absent = not artifact.file.opened
  if not absent:
    # Name/inode/version/extent checks bind prepared prefix validation to the still-held immutable resource.
    if not data.directory.sameDirectory(artifact.file): return refused[PagedReclamation](
        PagedNativeError.StaleView)
    let checked = artifact.file.check
    if checked != FileError.None: return fileFailed[PagedReclamation](checked)
    if artifact.sealed:
      let verified = validateFile(artifact.file, artifact.checked.manifest, data.config.limits)
      if verified.error != PagedStreamError.None: return streamFailed[PagedReclamation,
          CheckedPagedArtifact](verified)
  else:
    # Captured absence cannot authorize a newly created epoch with an equal counter after preparation.
    let exists = data.directory.epochExists(artifact.checked.manifest.epoch)
    if exists.error != FileError.None: return fileFailed[PagedReclamation](exists.error)
    if exists.value: return refused[PagedReclamation](PagedNativeError.StaleView)
  if artifact.sealed and not artifact.pending.opened:
    # A live complete seal independently defines staging bytes without requiring another producer replay.
    let pending = openPending(artifact.pending, data.directory)
    if pending.error != FileError.None: return fileFailed[PagedReclamation](pending.error)
  if artifact.pending.opened:
    # Recheck prefix bytes on every attempt; a failed staging comparison never turns into authority on retry.
    let checked = matchesPrefix(artifact.pending, artifact.checked.manifest.bytes,
        data.config.limits.work)
    if checked != FileError.None: return fileFailed[PagedReclamation](checked)
  else:
    let checked = data.directory.pendingAbsent
    if checked != FileError.None: return fileFailed[PagedReclamation](checked)
  let current = if artifact.initial: data.directory.initialAbsent else: current(data)
  if current != FileError.None: return fileFailed[PagedReclamation](current)
  if not absent:
    # No unlink occurs until every candidate/staging/source preflight above has passed.
    let removed = removePinned(data.directory, artifact.file)
    if removed != FileError.None:
      data.poisoned = true
      return fileFailed[PagedReclamation](removed)
  if artifact.pending.opened:
    let removed = removePinned(data.directory, artifact.pending)
    if removed != FileError.None:
      data.poisoned = true
      return fileFailed[PagedReclamation](removed)
  let confirmed = data.directory.synchronize
  if confirmed != FileError.None:
    data.poisoned = true
    return fileFailed[PagedReclamation](confirmed)
  let retired = candidate.close
  PagedNativeResult[PagedReclamation](status: PagedNativeError.None,
    completed: PagedReclamation(ready: true, absentBefore: absent, retirement: retired))

func rejected[T, U](outcome: PagedNativeResult[U]): PagedNativeResult[
    T] {.requires: outcome.status != PagedNativeError.None.} =
  ## Composite recovery preserves the exact selected cause and never manufactures an intermediate success payload.
  if outcome.error == PagedNativeError.FileFailure: return fileFailed[T](outcome.fileError)
  if outcome.error == PagedNativeError.StreamFailure:
    return PagedNativeResult[T](status: PagedNativeError.StreamFailure,
      streamCause: outcome.streamError,
      proofCause: (if outcome.streamError == PagedStreamError.ProofFailure: outcome.proofError else: StateProofError.Uninitialized))
  refused[T](outcome.error)
proc resumePagedInitialization*(writer: var PagedWriter, path: string, config: PagedNativeConfig,
    producer: nil PagedProducer, count, payload: uint64, context: openArray[byte] = [
        ]): PagedNativeResult[PagedPublication] =
  ## Explicit replay of an interrupted bootstrap requires existing LOCK, CURRENT absence and independently expected initial evidence.
  if writer.opened: return fileFailed[PagedPublication](FileError.Busy)
  if producer == nil: return refused[PagedPublication](PagedNativeError.Uninitialized)
  let contextPolicy = validatePagedContextSize(uint64(context.len), config.limits.contextBytes)
  if contextPolicy != PagedStreamError.None:
    return PagedNativeResult[PagedPublication](status: PagedNativeError.StreamFailure,
        streamCause: contextPolicy)
  let header = initPagedHeader(config.chain, config.root, ManagedEpoch(1), LightDeltaSequence(0),
      count, payload, config.limits.dataset, uint64(context.len))
  if header.error != PagedCodecError.None: return fileFailed[PagedPublication](
      FileError.LimitExceeded)
  var data = WriterData(config: config, poisoned: true)
  let acquired = openDirectory(data.directory, path, false, true)
  if acquired != FileError.None:
    if data.directory.opened:
      let retired = data.directory.close
      if retired != FileError.None: return fileFailed[PagedPublication](retired)
    return fileFailed[PagedPublication](acquired)
  data.active = true
  writer.data = data
  var candidate = default(PagedCandidate)
  defer:
    if candidate.opened:
      let retired = candidate.close
      if retired != FileError.None: result = fileFailed[PagedPublication](retired)
  let replayed = prepareCleanup(data, candidate, default(PagedManifest), header.value, producer,
      true, context)
  if replayed.error != PagedNativeError.None: return rejected[PagedPublication, bool](replayed)
  let cleanup = candidate.data
  assert cleanup != nil
  let expected = cleanup.checked.manifest.bytes
  let removed = discardPagedCandidate(writer, candidate, default(PagedManifest))
  if removed.error != PagedNativeError.None: return rejected[PagedPublication, PagedReclamation](removed)
  if removed.value.retirementError != FileError.None: return fileFailed[PagedPublication](
      removed.value.retirementError)
  let prepared = prepare(data, candidate, producer, config.root, count, payload,
      PagedBuildKind.Replacement, true, context)
  if prepared.error != PagedNativeError.None: return rejected[PagedPublication, StorageDurability](prepared)
  let authored = candidate.data
  assert authored != nil
  if authored.checked.manifest.bytes != expected:
    return PagedNativeResult[PagedPublication](status: PagedNativeError.StreamFailure,
        streamCause: PagedStreamError.ChangedInput)
  writer.publish(candidate)

proc readProof*(reader: var PagedReader, query: StateKey,
    budget: PagedWorkLimits): PagedNativeResult[PagedProofLookup] =
  ## No cache page or native owner escapes: only immutable bounded proof transport may outlive close.
  let data = reader.data
  if data == nil or not data.active: return refused[PagedProofLookup](
      PagedNativeError.Uninitialized)
  if data.poisoned: return refused[PagedProofLookup](PagedNativeError.RecoveryRequired)
  let checked = proofFile(data.file, data.checked, query, budget)
  if checked.error != PagedStreamError.None:
    if data.file.check != FileError.None: data.poisoned = true
    return streamFailed[PagedProofLookup, PagedProofLookup](checked)
  PagedNativeResult[PagedProofLookup](status: PagedNativeError.None,
      completed: checked.value)

func failure*[T](outcome: PagedNativeResult[T]): PagedNativeResult[bool] {.requires:
    outcome.status != PagedNativeError.None.} =
  ## Composite consumers retain original selected causes without a successful native payload.
  rejected[bool, T](outcome)

proc readContext*(reader: var PagedReader, budget: PagedWorkLimits): PagedNativeResult[PagedContext] =
  ## Owned opaque context outlives its immutable reader without changing proof or checkpoint trust.
  let data = reader.data
  if data == nil or not data.active: return refused[PagedContext](PagedNativeError.Uninitialized)
  if data.poisoned: return refused[PagedContext](PagedNativeError.RecoveryRequired)
  let captured = contextFile(data.file, data.checked, budget)
  if captured.error != PagedStreamError.None:
    if data.file.check != FileError.None: data.poisoned = true # Native read uncertainty requires explicit retirement.
    return streamFailed[PagedContext, PagedContext](captured)
  PagedNativeResult[PagedContext](status: PagedNativeError.None, completed: captured.value)
proc readContext*(writer: var PagedWriter, budget: PagedWorkLimits): PagedNativeResult[PagedContext] =
  ## Startup inspects only the already admitted selected head while retaining its exclusive writer lease.
  let data = writer.data
  if data == nil or not data.active or not data.selected: return refused[PagedContext](
      PagedNativeError.Uninitialized)
  if data.poisoned: return refused[PagedContext](PagedNativeError.RecoveryRequired)
  let captured = contextFile(data.head, data.checked, budget)
  if captured.error != PagedStreamError.None:
    if data.head.check != FileError.None: data.poisoned = true # Preserve native failure quarantine before subsequent operations.
    return streamFailed[PagedContext, PagedContext](captured)
  PagedNativeResult[PagedContext](status: PagedNativeError.None, completed: captured.value)

proc queryInventory*(reader: var PagedReader, maximum: ElementLimit,
    budget: PagedWorkLimits): PagedNativeResult[PagedQueryInventory] =
  ## Detached keys outlive the reader; root trust remains independently supplied and no native resource escapes.
  let data = reader.data
  if data == nil or not data.active: return refused[PagedQueryInventory](
      PagedNativeError.Uninitialized) # Default/closed owners grant no readable source.
  if data.poisoned: return refused[PagedQueryInventory](
      PagedNativeError.RecoveryRequired) # Failed native identity/IO cannot revive a source.
  let captured = queryInventoryFile(data.file, data.checked, maximum, budget)
  if captured.error != PagedStreamError.None:
    if data.file.check != FileError.None: data.poisoned = true # Pure quota refusal is separate from native uncertainty.
    return streamFailed[PagedQueryInventory, PagedQueryInventory](captured)
  PagedNativeResult[PagedQueryInventory](status: PagedNativeError.None, completed: captured.value)
proc synchronize*(writer: var PagedWriter): PagedNativeResult[StorageDurability] =
  ## Confirm actual selected-file and directory barriers under the held exact current source and writer lease.
  let data = writer.data
  if data == nil or not data.active: return refused[StorageDurability](
      PagedNativeError.Uninitialized) # No remembered receipt can stand in for an open owner.
  let selected = current(data)
  if selected != FileError.None: return fileFailed[StorageDurability](
      selected) # Fresh fencing precedes both barriers.
  let file = data.head.synchronize
  if file != FileError.None:
    data.poisoned = true # Failed fresh durability requires explicit reopen before another mutation.
    return fileFailed[StorageDurability](file)
  let directory = data.directory.synchronize
  if directory != FileError.None:
    data.poisoned = true # A file barrier alone does not grant the complete durability receipt.
    return fileFailed[StorageDurability](directory)
  PagedNativeResult[StorageDurability](status: PagedNativeError.None,
      completed: StorageDurability.FileAndDirectorySynced)
