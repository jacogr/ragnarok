# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Storage-only durable paged-light owners: exclusive writers, sealed candidates and independent pinned readers.
## Complete stream verification precedes selection. Explicit close and passive post-confirmation diagnostics preserve uncertainty.
import std/assertions
import ./[paged_io, paged_codec, paged_stream, managed_manifest, light_delta, database_identity,
  file_errors, durability, state_proof]
import ../codec/[bounded, state_layout, state_trie]

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
  WriterData = ref object ## Stable private writer incarnation binds candidate preparation without descriptor-number ABA.
    directory: PagedDirectory
    head: PagedFile
    active, poisoned, selected: bool
    config: PagedNativeConfig
    checked: CheckedPagedArtifact
  PagedWriter* = object ## Sole writer-lease/selected-handle retirement authority; it owns no retained reader.
    data: nil WriterData
  CandidateData = ref object ## A candidate retains the original writer incarnation but never prolongs its native lease after close.
    file: PagedFile
    owner: WriterData
    source: PagedManifest
    checked: CheckedPagedArtifact
    active, sealed, initial: bool
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
proc `=destroy`*(writer: PagedWriter) =
  ## Default/moved values pass; live leases require explicit close.
  closed(writer)
  `=destroy`(writer.data)
proc `=destroy`*(candidate: PagedCandidate) =
  ## Explicit close preserves forensic files and reports native retirement failure.
  closed(candidate)
  `=destroy`(candidate.data)
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
  if data.file.opened: data.file.close else: FileError.None
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
      ByteLimit(PagedManifestBytes))
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
      ByteLimit(PagedManifestBytes))
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
    root: StateRoot, count, payload: uint64, advance, initial: bool): PagedNativeResult[
        StorageDurability] =
  ## Bind a new exclusive authoring owner to one live writer incarnation and exact source position/policies.
  if candidate.opened: return fileFailed[StorageDurability](FileError.Busy)
  if producer == nil: return refused[StorageDurability](PagedNativeError.Uninitialized)
  if not data.active: return refused[StorageDurability](PagedNativeError.Uninitialized)
  if not initial and data.poisoned: return refused[StorageDurability](
      PagedNativeError.RecoveryRequired)
  var epoch = 1'u64
  var sequence = 0'u64
  var source = default(PagedManifest)
  if not initial:
    source = data.checked.manifest
    if uint64(source.epoch) == high(uint64) or (not advance and uint64(source.sequence) == high(uint64)):
      return refused[StorageDurability](PagedNativeError.CounterExhausted)
    epoch = uint64(source.epoch)+1
    sequence = uint64(source.sequence)
    if not advance: inc sequence
    let checked = validateHead(data)
    if checked.error != PagedNativeError.None:
      if checked.error == PagedNativeError.FileFailure: return fileFailed[StorageDurability](
          checked.fileError)
      return PagedNativeResult[StorageDurability](status: PagedNativeError.StreamFailure,
        streamCause: checked.streamError, proofCause: (if checked.streamError ==
            PagedStreamError.ProofFailure: checked.proofError else: StateProofError.Uninitialized))
  let header = initPagedHeader(data.config.chain, root, ManagedEpoch(epoch), LightDeltaSequence(
      sequence), count, payload, data.config.limits.dataset)
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
  let authoring = buildFile(artifact.file, producer, header.value, data.config.limits)
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
    producer: nil PagedProducer, count, payload: uint64): PagedNativeResult[StorageDurability] =
  ## Same-root full replacement advances ordinary sequence once, even for explicitly requested equal evidence.
  let data = writer.data
  if data == nil: return refused[StorageDurability](PagedNativeError.Uninitialized)
  prepare(data, candidate, producer, data.config.root, count, payload, false, false)
proc preparePagedAdvance*(writer: var PagedWriter, candidate: var PagedCandidate,
    destination: StateRoot, producer: nil PagedProducer, count, payload: uint64): PagedNativeResult[
        StorageDurability] =
  ## Destination trust is explicit; all destination evidence is fresh and ordinary sequence is preserved.
  let data = writer.data
  if data == nil: return refused[StorageDurability](PagedNativeError.Uninitialized)
  if array[32, byte](destination) == array[32, byte](data.config.root): return refused[
      StorageDurability](PagedNativeError.InvalidTransition)
  prepare(data, candidate, producer, destination, count, payload, true, false)
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
    producer: nil PagedProducer, count, payload: uint64): PagedNativeResult[PagedPublication] =
  ## Exclusive bootstrap starts at epoch one/sequence zero; acquired failed namespaces require explicit writer close.
  if writer.opened: return fileFailed[PagedPublication](FileError.Busy)
  if producer == nil: return refused[PagedPublication](PagedNativeError.Uninitialized)
  let header = initPagedHeader(config.chain, config.root, ManagedEpoch(1), LightDeltaSequence(0),
      count, payload, config.limits.dataset)
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
  let prepared = prepare(data, candidate, producer, config.root, count, payload, false, true)
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
func policy(limits: PagedStreamLimits): array[14, uint64] =
  ## Exact immutable policy binding covers all dataset/proof/cache/work ceilings, including zero allowances.
  [uint64(limits.dataset.entries), uint64(limits.dataset.bytes), uint64(limits.proof.nodes),
    uint64(limits.proof.valueBytes), uint64(limits.workingBytes), uint64(limits.cachePages),
    uint64(limits.work.ioCalls), uint64(limits.work.producerCalls), uint64(limits.work.pageHashes),
    uint64(limits.work.proofs), uint64(limits.work.nodes), uint64(limits.work.readBytes),
    uint64(limits.work.writeBytes), uint64(limits.work.valueBytes)]
proc reclaim*(writer: var PagedWriter, receipt: PagedEpochReceipt,
    expected: PagedManifest): PagedNativeResult[PagedReclamation] =
  ## Remove only one captured older inode after source validation and an independent exclusive nonblocking pin.
  let data = writer.data
  if data == nil or not data.active: return refused[PagedReclamation](
      PagedNativeError.Uninitialized)
  if data.poisoned: return refused[PagedReclamation](PagedNativeError.RecoveryRequired)
  if not receipt.ready or not expected.initialized: return refused[PagedReclamation](
      PagedNativeError.InvalidCandidate)
  if expected.bytes != data.checked.manifest.bytes: return refused[PagedReclamation](
      PagedNativeError.StaleView)
  if uint64(receipt.selected.epoch) >= uint64(expected.epoch): return refused[PagedReclamation](
      PagedNativeError.InvalidCandidate)
  if array[32, byte](receipt.config.chain) != array[32, byte](data.config.chain) or
      policy(receipt.config.limits) != policy(data.config.limits) or
          not data.directory.matchesDirectory(receipt.identity):
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
  let exists = data.directory.epochExists(receipt.selected.epoch)
  if exists.error != FileError.None: return fileFailed[PagedReclamation](exists.error)
  if not exists.value:
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
  let pinned = openEpoch(file, data.directory, receipt.selected.epoch, PagedPin.Exclusive,
      receipt.config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[PagedReclamation](pinned)
  let actual = file.fileIdentity
  if actual.error != FileError.None: return fileFailed[PagedReclamation](actual.error)
  if not receipt.identity.matches(actual.value): return fileFailed[PagedReclamation](
      FileError.RecoveryMismatch)
  let verified = validateFile(file, receipt.selected, receipt.config.limits)
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
