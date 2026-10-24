# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Durable full-state paged writers, sealed candidates and readers require complete graph admission.
## Explicit close exposes retirement uncertainty; no reader owns a writer lease, callback or resident graph.
## One caller serializes operations per owner; independent readers have independent native seek cursors.
import std/assertions
import ./[full_paged_codec, full_paged_stream, paged_io, paged_codec, database_identity,
  file_errors, full_paged_build, durability,
  managed_manifest, node_repository]
import ../codec/[bounded, state_layout, state_trie]

type
  FullPagedNativeError* {.pure.} = enum ## Failed/default native results contain no retained reader or graph receipt.
    Uninitialized, None, FileFailure, CodecFailure, GraphFailure, BuildFailure,
    RecoveryRequired, StaleView, CounterExhausted, InvalidCandidate
  FullPagedNativeResult*[T] = object ## Private selected alternatives retain only their precise diagnostic.
    case status: FullPagedNativeError
    of None: completed: T
    of FileFailure: fileCause: FileError
    of CodecFailure: codecCause: FullPagedError
    of GraphFailure:
      graphCause: FullPagedStreamError
      graphCodec: FullPagedError
    of BuildFailure:
      buildCause: FullPagedBuildError
      buildCodec: FullPagedError
      buildGraph: FullPagedStreamError
      buildGraphCodec: FullPagedError
    else: discard
  FullPagedConstructionLimits* = object ## Native authoring ceilings never replace inherited full-admission policies.
    producerCalls*, ioCalls*, hashes*: ElementLimit
    readBytes*, writeBytes*: ByteLimit
  FullPagedNativeConfig* = object ## Expected chain/root and finite policy are selected independently of disk.
    chain*: StorageChainId
    root*: StateRoot
    limits*: FullPagedStreamLimits
    construction*: FullPagedConstructionLimits
  ReaderData = ref object ## One immutable native pin; only explicit retirement can release its descriptor.
    file: PagedFile
    checked: CheckedFullPagedArtifact
    active: bool
  FullPagedReader* = object ## Unique explicit-close reader authority survives directory/writer retirement.
    data: nil ReaderData
  WriterData = ref object ## Stable incarnation owns the writer lease and one selected complete native epoch.
    directory: PagedDirectory
    head: PagedFile
    config: FullPagedNativeConfig
    checked: CheckedFullPagedArtifact
    active, poisoned, selected: bool
  FullPagedWriter* = object ## Unique writer retirement authority; candidates do not prolong its lease after close.
    data: nil WriterData
  CandidateData = ref object ## Sealed authoring capability binds exact writer incarnation and selected predecessor.
    file: PagedFile
    owner: WriterData
    checked: CheckedFullPagedArtifact
    source: FullPagedManifest
    active, sealed, initial: bool
  FullPagedCandidate* = object ## Failed authoring may still own a forensic file and requires explicit close.
    data: nil CandidateData
  FullPagedPublication* = object ## Confirmed selection remains success independently of later retirement diagnostics.
    ready: bool
    selected: FullPagedManifest
    retirement: FileError
    usable: bool
  FullPagedEpochReceipt* = object ## Captured old checked identity is passive and owns no native pin or writer incarnation.
    ready: bool
    header: FullPagedHeader
    selected: FullPagedManifest
    identity: PagedFileIdentity
    limits: FullPagedStreamLimits
  FullPagedReclamation* = object ## Confirmed absence survives later close diagnostics; uncertainty exposes no successful deletion prefix.
    ready: bool
    absentBefore: bool
    retirement: FileError
func opened*(writer: FullPagedWriter): bool =
  ## Default/moved/closed writers have no native retirement authority.
  let data = writer.data
  data != nil and data.active
func opened*(candidate: FullPagedCandidate): bool =
  ## Both forensic and sealed candidates own their independent file descriptor until close.
  let data = candidate.data
  data != nil and data.active
proc `=copy`*(destination: var FullPagedWriter, source: FullPagedWriter) {.error.}
  ## Writer leases and selected native descriptors have exactly one close owner.
proc `=dup`*(source: FullPagedWriter): FullPagedWriter {.error.}
  ## Actual lowering rejects implicit writer retirement duplication.
proc `=copy`*(destination: var FullPagedCandidate, source: FullPagedCandidate) {.error.}
  ## Prepared capabilities cannot be duplicated through composite ARC copies.
proc `=dup`*(source: FullPagedCandidate): FullPagedCandidate {.error.}
  ## A second native owner would invalidate exact candidate retirement authority.
proc closed(writer: FullPagedWriter) {.requires: not writer.opened.} =
  ## Live leases require explicit error-aware retirement.
  discard
proc closed(candidate: FullPagedCandidate) {.requires: not candidate.opened.} =
  ## Even failed authoring must retire its forensic descriptor explicitly.
  discard
proc `=destroy`*(writer: FullPagedWriter) =
  ## Default/moved values release only their managed private reference; live resources require close.
  closed(writer)
  `=destroy`(writer.data)
proc `=destroy`*(candidate: FullPagedCandidate) =
  ## A retained incarnation reference never grants destructor permission to silently close live native resources.
  closed(candidate)
  `=destroy`(candidate.data)
func opened*(reader: FullPagedReader): bool =
  ## Default, moved and closed values own no retirement obligation.
  let data = reader.data
  data != nil and data.active
proc `=copy`*(destination: var FullPagedReader, source: FullPagedReader) {.error.}
  ## Independent readers require independent native opens and shared pins.
proc `=dup`*(source: FullPagedReader): FullPagedReader {.error.}
  ## Actual ARC lowering must reject hidden duplication of a native retirement owner.
proc closed(reader: FullPagedReader) {.requires: not reader.opened.} =
  ## A live native descriptor cannot silently disappear through a destructor.
  discard
proc `=destroy`*(reader: FullPagedReader) =
  ## Moved/default values are harmless; a live native owner requires explicit error-aware close.
  closed(reader)
  `=destroy`(reader.data)
func error*[T](outcome: FullPagedNativeResult[T]): FullPagedNativeError =
  ## Observe only the selected native result alternative.
  outcome.status
func value*[T](outcome: FullPagedNativeResult[T]): T {.inline,
    requires: outcome.status == FullPagedNativeError.None.} =
  ## Success is mandatory before extracting a reader operation or passive receipt.
  outcome.completed
func fileError*[T](outcome: FullPagedNativeResult[T]): FileError {.requires:
    outcome.status == FullPagedNativeError.FileFailure.} =
  ## Read only a selected native-resource cause.
  outcome.fileCause
func codecError*[T](outcome: FullPagedNativeResult[T]): FullPagedError {.requires:
    outcome.status == FullPagedNativeError.CodecFailure.} =
  ## Shape/checksum/identity failures remain distinct from incomplete graph failures.
  outcome.codecCause
func graphError*[T](outcome: FullPagedNativeResult[T]): FullPagedStreamError {.requires:
    outcome.status == FullPagedNativeError.GraphFailure.} =
  ## Missing records are graph corruption, never a successful absent lookup.
  outcome.graphCause
func graphCodecError*[T](outcome: FullPagedNativeResult[T]): FullPagedError {.requires:
    outcome.status == FullPagedNativeError.GraphFailure.} =
  ## Non-codec graph refusals preserve only an uninitialized subordinate codec reason.
  outcome.graphCodec
func fileFailed[T](reason: FileError): FullPagedNativeResult[T] =
  ## No native IO refusal carries success metadata.
  FullPagedNativeResult[T](status: FullPagedNativeError.FileFailure, fileCause: reason)
func codecFailed[T](reason: FullPagedError): FullPagedNativeResult[T] =
  ## Local manifest/header refusal cannot grant graph authority.
  FullPagedNativeResult[T](status: FullPagedNativeError.CodecFailure, codecCause: reason)
func graphFailed[T, U](outcome: FullPagedStreamResult[U]): FullPagedNativeResult[T] =
  ## Preserve graph failure and its selected local codec cause without copying inactive variants.
  let reason = if outcome.error == FullPagedStreamError.CodecFailure: outcome.codecError else:
    FullPagedError.Uninitialized
  FullPagedNativeResult[T](status: FullPagedNativeError.GraphFailure,
    graphCause: outcome.error, graphCodec: reason)
proc close*(reader: var FullPagedReader): FileError =
  ## Mark ownership retired before the single native close; EINTR never retries a reused descriptor number.
  let data = reader.data
  if data == nil or not data.active: return FileError.Uninitialized
  data.active = false
  reader.data = nil
  if data.file.opened: data.file.close else: FileError.None
proc openFullPagedReader*(reader: var FullPagedReader, path: string,
    config: FullPagedNativeConfig): FullPagedNativeResult[bool] =
  ## CURRENT read, independent shared pin, complete admission and CURRENT reread exclude selection races.
  if reader.opened: return fileFailed[bool](FileError.Busy)
  var directory = default(PagedDirectory)
  var file = default(PagedFile)
  defer:
    # No failed open leaks a half-admitted resource, including anonymous scratch or parent descriptors.
    if file.opened and file.close != FileError.None: result = fileFailed[bool](FileError.IoFailure)
    if directory.opened and directory.close != FileError.None:
      result = fileFailed[bool](FileError.IoFailure)
  let opened = openDirectory(directory, path, false, false)
  if opened != FileError.None: return fileFailed[bool](opened)
  let current = directory.readFullCurrent
  if current.error != FileError.None: return fileFailed[bool](current.error)
  let selected = decodeFullPagedSelection(current.value, config.chain, config.root,
      config.limits.dataset)
  if selected.error != FullPagedError.None: return codecFailed[bool](selected.error)
  let pinned = openEpoch(file, directory, selected.value.epoch, PagedPin.Shared,
      config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[bool](pinned)
  let header = file.readFullHeader(config.chain, config.root, config.limits.dataset)
  if header.error != FileError.None: return fileFailed[bool](header.error)
  if header.value.error != FullPagedError.None: return codecFailed[bool](header.value.error)
  let binding = decodeFullPagedManifest(current.value, header.value.value)
  if binding.error != FullPagedError.None: return codecFailed[bool](binding.error)
  let admitted = file.validateFullFile(directory, header.value.value, selected.value, config.limits)
  if admitted.error != FileError.None: return fileFailed[bool](admitted.error)
  if admitted.value.error != FullPagedStreamError.None: return graphFailed[bool,
      CheckedFullPagedArtifact](admitted.value)
  let again = directory.readFullCurrent
  if again.error != FileError.None: return fileFailed[bool](again.error)
  if current.value != again.value: return fileFailed[bool](FileError.StaleView)
  let checked = file.check
  if checked != FileError.None: return fileFailed[bool](checked)
  let retired = directory.close
  if retired != FileError.None: return fileFailed[bool](retired)
  reader.data = ReaderData(file: move(file), checked: admitted.value.value, active: true)
  FullPagedNativeResult[bool](status: FullPagedNativeError.None, completed: true)
proc selected*(reader: FullPagedReader): FullPagedNativeResult[FullPagedManifest] =
  ## A passive selected receipt describes this held reader, independent of later CURRENT changes.
  let data = reader.data
  if data == nil or not data.active:
    return FullPagedNativeResult[FullPagedManifest](status: FullPagedNativeError.Uninitialized)
  let checked = data.file.check
  if checked != FileError.None: return fileFailed[FullPagedManifest](checked)
  FullPagedNativeResult[FullPagedManifest](status: FullPagedNativeError.None,
    completed: data.checked.manifest)
proc lookup*(reader: FullPagedReader, root: StateRoot,
    key: StateKey): FullPagedNativeResult[FullPagedLookup] =
  ## Owned presence/absence results outlive reader close; an unknown retained root is an explicit refusal.
  let data = reader.data
  if data == nil or not data.active:
    return FullPagedNativeResult[FullPagedLookup](status: FullPagedNativeError.Uninitialized)
  let found = data.file.lookupFullFile(data.checked, root, key)
  if found.error != FullPagedStreamError.None: return graphFailed[FullPagedLookup, FullPagedLookup](found)
  FullPagedNativeResult[FullPagedLookup](status: FullPagedNativeError.None, completed: found.value)
func refused[T](reason: FullPagedNativeError): FullPagedNativeResult[T] =
  ## Ordinary refusal reasons carry no typed failure payload or fallback native owner.
  FullPagedNativeResult[T](status: reason)
func buildFailed[T](outcome: FullPagedBuildResult): FullPagedNativeResult[T] =
  ## Preserve authoring and selected subordinate diagnostics without granting a partially built artifact.
  let codec = if outcome.error == FullPagedBuildError.CodecFailure: outcome.codecError else:
    FullPagedError.Uninitialized
  let graph = if outcome.error == FullPagedBuildError.GraphFailure: outcome.graphError else:
    FullPagedStreamError.Uninitialized
  let graphCodec = if outcome.error == FullPagedBuildError.GraphFailure: outcome.graphCodecError else:
    FullPagedError.Uninitialized
  FullPagedNativeResult[T](status: FullPagedNativeError.BuildFailure,
    buildCause: outcome.error, buildCodec: codec, buildGraph: graph, buildGraphCodec: graphCodec)
func buildError*[T](outcome: FullPagedNativeResult[T]): FullPagedBuildError {.requires:
    outcome.status == FullPagedNativeError.BuildFailure.} =
  ## Observe only a selected construction refusal.
  outcome.buildCause
func buildCodecError*[T](outcome: FullPagedNativeResult[T]): FullPagedError {.requires:
    outcome.status == FullPagedNativeError.BuildFailure.} =
  ## Non-codec construction failures carry only Uninitialized in this subordinate slot.
  outcome.buildCodec
func rejected[T, U](outcome: FullPagedNativeResult[U]): FullPagedNativeResult[T] {.requires:
    outcome.status != FullPagedNativeError.None.} =
  ## Composite operations preserve the exact selected refusal while changing only their successful payload type.
  if outcome.error == FullPagedNativeError.FileFailure: return fileFailed[T](outcome.fileError)
  if outcome.error == FullPagedNativeError.CodecFailure: return codecFailed[T](outcome.codecError)
  if outcome.error == FullPagedNativeError.GraphFailure:
    return FullPagedNativeResult[T](status: FullPagedNativeError.GraphFailure,
      graphCause: outcome.graphCause, graphCodec: outcome.graphCodec)
  if outcome.error == FullPagedNativeError.BuildFailure:
    return FullPagedNativeResult[T](status: FullPagedNativeError.BuildFailure,
      buildCause: outcome.buildCause, buildCodec: outcome.buildCodec,
      buildGraph: outcome.buildGraph, buildGraphCodec: outcome.buildGraphCodec)
  refused[T](outcome.error)
func manifest*(receipt: FullPagedPublication): FullPagedManifest {.requires: receipt.ready.} =
  ## Confirmed file/directory synchronization precedes this passive selected receipt.
  receipt.selected
func retirementError*(receipt: FullPagedPublication): FileError {.requires: receipt.ready.} =
  ## Retirement uncertainty does not erase an already confirmed durable selection.
  receipt.retirement
func writerUsable*(receipt: FullPagedPublication): bool {.requires: receipt.ready.} =
  ## False requires explicit close/reopen even though selection is confirmed.
  receipt.usable
func durability*(receipt: FullPagedPublication): StorageDurability {.requires: receipt.ready.} =
  ## This receipt attests completed OS barriers, without claiming hardware power-loss qualification.
  StorageDurability.FileAndDirectorySynced
proc close*(candidate: var FullPagedCandidate): FileError =
  ## Closing a failed or sealed candidate never deletes its forensic physical artifact.
  let data = candidate.data
  if data == nil or not data.active: return FileError.Uninitialized
  data.active = false
  candidate.data = nil
  if data.file.opened: data.file.close else: FileError.None
proc close*(writer: var FullPagedWriter): FileError =
  ## Retire the selected file and stable lease once; independently retained readers/candidates remain separate.
  let data = writer.data
  if data == nil or not data.active: return FileError.Uninitialized
  data.active = false
  writer.data = nil
  var reason = FileError.None
  if data.head.opened: reason = data.head.close
  if data.directory.opened:
    # Always attempt lease/directory retirement even after selected-file close uncertainty.
    let retired = data.directory.close
    if reason == FileError.None: reason = retired
  reason
proc current(data: WriterData): FileError =
  ## A remembered source is usable only while the exact lease, selected bytes and immutable inode remain held.
  if not data.active: return FileError.Uninitialized
  if data.poisoned or not data.selected: return FileError.RecoveryRequired
  let held = data.directory.check
  if held != FileError.None:
    data.poisoned = true
    return held
  let current = data.directory.readFullCurrent
  if current.error != FileError.None:
    data.poisoned = true
    return current.error
  let expected = data.checked.manifest.bytes
  if expected.error != FullPagedError.None: return FileError.BackendFailure
  for index in 0..<FullPagedManifestBytes:
    # Exact fixed width was established by readFullCurrent before comparing each selected byte.
    if expected.value[index] != current.value[index]:
      data.poisoned = true
      return FileError.StaleView
  let pinned = data.head.check
  if pinned != FileError.None: data.poisoned = true
  pinned
proc validateHead(data: WriterData): FullPagedNativeResult[bool] =
  ## Complete source graph admission is repeated before authoring or selecting any successor.
  let held = current(data)
  if held != FileError.None: return fileFailed[bool](held)
  let admitted = data.head.validateFullFile(data.directory, data.checked.header,
    data.checked.manifest, data.config.limits)
  if admitted.error != FileError.None: return fileFailed[bool](admitted.error)
  if admitted.value.error != FullPagedStreamError.None:
    return graphFailed[bool, CheckedFullPagedArtifact](admitted.value)
  FullPagedNativeResult[bool](status: FullPagedNativeError.None, completed: true)
proc selected*(writer: FullPagedWriter): FullPagedNativeResult[FullPagedManifest] =
  ## Passive metadata never repairs stale CURRENT or revives an uncertain writer.
  let data = writer.data
  if data == nil or not data.active: return refused[FullPagedManifest](
      FullPagedNativeError.Uninitialized)
  let held = current(data)
  if held != FileError.None: return fileFailed[FullPagedManifest](held)
  FullPagedNativeResult[FullPagedManifest](status: FullPagedNativeError.None,
      completed: data.checked.manifest)
proc openFullPagedWriter*(writer: var FullPagedWriter, path: string,
    config: FullPagedNativeConfig): FullPagedNativeResult[bool] =
  ## Existing full CURRENT must match independently expected chain/root after acquiring the stable writer lease.
  if writer.opened: return fileFailed[bool](FileError.Busy)
  let data = WriterData(config: config)
  defer:
    # A failed open exposes neither selected authority nor an unreleased partial lease.
    if writer.data == nil:
      if data.head.opened and data.head.close != FileError.None: result = fileFailed[bool](
          FileError.IoFailure)
      if data.directory.opened and data.directory.close != FileError.None:
        result = fileFailed[bool](FileError.IoFailure)
  let opened = openDirectory(data.directory, path, false, true)
  if opened != FileError.None: return fileFailed[bool](opened)
  let current = data.directory.readFullCurrent
  if current.error != FileError.None: return fileFailed[bool](current.error)
  let selected = decodeFullPagedSelection(current.value, config.chain, config.root,
      config.limits.dataset)
  if selected.error != FullPagedError.None: return codecFailed[bool](selected.error)
  let pinned = openEpoch(data.head, data.directory, selected.value.epoch,
    PagedPin.Shared, config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[bool](pinned)
  let header = data.head.readFullHeader(config.chain, config.root, config.limits.dataset)
  if header.error != FileError.None: return fileFailed[bool](header.error)
  if header.value.error != FullPagedError.None: return codecFailed[bool](header.value.error)
  let binding = decodeFullPagedManifest(current.value, header.value.value)
  if binding.error != FullPagedError.None: return codecFailed[bool](binding.error)
  let admitted = data.head.validateFullFile(data.directory, header.value.value, selected.value, config.limits)
  if admitted.error != FileError.None: return fileFailed[bool](admitted.error)
  if admitted.value.error != FullPagedStreamError.None:
    return graphFailed[bool, CheckedFullPagedArtifact](admitted.value)
  let again = data.directory.readFullCurrent
  if again.error != FileError.None: return fileFailed[bool](again.error)
  if current.value != again.value: return fileFailed[bool](FileError.StaleView)
  data.checked = admitted.value.value
  data.active = true
  data.selected = true
  writer.data = data
  FullPagedNativeResult[bool](status: FullPagedNativeError.None, completed: true)
func buildLimits(config: FullPagedNativeConfig): FullPagedBuildLimits =
  ## Inherited admission policy cannot be substituted by a separate construction-budget object.
  let work = config.construction
  FullPagedBuildLimits(admission: config.limits, producerCalls: work.producerCalls,
    ioCalls: work.ioCalls, hashes: work.hashes, readBytes: work.readBytes,
    writeBytes: work.writeBytes)
proc prepare(data: WriterData, candidate: var FullPagedCandidate, root: StateRoot,
    roots: openArray[FullPagedRoot], producer: nil FullPagedProducer, count, payload: uint64,
    initial: bool): FullPagedNativeResult[StorageDurability] =
  ## Exact predecessor and writer incarnation bind each sealed complete target to one live publication authority.
  if candidate.opened: return fileFailed[StorageDurability](FileError.Busy)
  if not data.active or producer == nil: return refused[StorageDurability](
      FullPagedNativeError.Uninitialized)
  if data.poisoned and not initial: return refused[StorageDurability](
      FullPagedNativeError.RecoveryRequired)
  var epoch = 1'u64
  var generation = 0'u64
  var source = default(FullPagedManifest)
  if not initial:
    # Ordinary full-state replacement advances both physical epoch and local repository generation.
    let header = data.checked.header
    if uint64(header.epoch) == high(uint64) or uint64(header.generation) == high(uint64):
      return refused[StorageDurability](FullPagedNativeError.CounterExhausted)
    epoch = uint64(header.epoch)+1
    generation = uint64(header.generation)+1
    let checked = validateHead(data)
    if checked.error != FullPagedNativeError.None: return rejected[StorageDurability, bool](checked)
    source = data.checked.manifest
  let header = initFullPagedHeader(data.config.chain, root, ManagedEpoch(epoch),
    RepositoryGeneration(generation), count, payload, roots, data.config.limits.dataset)
  if header.error != FullPagedError.None: return codecFailed[StorageDurability](header.error)
  let policy = validateFullPagedPolicy(data.config.limits)
  if policy != FullPagedStreamError.None:
    return FullPagedNativeResult[StorageDurability](status: FullPagedNativeError.GraphFailure,
      graphCause: policy, graphCodec: FullPagedError.Uninitialized)
  let limits = buildLimits(data.config)
  if header.value.geometry.byteLength > uint64(limits.writeBytes) or
      count > uint64(data.config.limits.scratchBytes) div 2 or
      uint64(roots.len) > uint64(data.config.limits.roots):
    return fileFailed[StorageDurability](FileError.LimitExceeded)
  if count >= high(uint64) div 2 or (count+1)*2 > uint64(limits.producerCalls):
    return fileFailed[StorageDurability](FileError.LimitExceeded)
  let empty = data.directory.pendingAbsent
  if empty != FileError.None: return fileFailed[StorageDurability](empty)
  let artifact = CandidateData(owner: data, source: source, initial: initial)
  let created = openEpoch(artifact.file, data.directory, ManagedEpoch(epoch), PagedPin.Create,
    data.config.limits.dataset.bytes)
  if created != FileError.None:
    # Partial native setup still has one explicit retirement owner before returning failure.
    if artifact.file.opened and artifact.file.close != FileError.None:
      return fileFailed[StorageDurability](FileError.IoFailure)
    return fileFailed[StorageDurability](created)
  artifact.active = true
  candidate.data = artifact
  let authored = buildFullFile(artifact.file, data.directory, producer, header.value, limits)
  if authored.error != FileError.None: return fileFailed[StorageDurability](authored.error)
  if authored.value.error != FullPagedBuildError.None: return buildFailed[StorageDurability](authored.value)
  let synced = artifact.file.synchronize
  if synced != FileError.None: return fileFailed[StorageDurability](synced)
  let durable = data.directory.synchronize
  if durable != FileError.None: return fileFailed[StorageDurability](durable)
  artifact.checked = authored.value.value.checked
  artifact.sealed = true
  FullPagedNativeResult[StorageDurability](status: FullPagedNativeError.None,
    completed: StorageDurability.FileAndDirectorySynced)
proc prepareFullPagedReplacement*(writer: var FullPagedWriter, candidate: var FullPagedCandidate,
    root: StateRoot, roots: openArray[FullPagedRoot], producer: nil FullPagedProducer,
    count, payload: uint64): FullPagedNativeResult[StorageDurability] =
  ## Explicit complete replacement chooses an independently expected target root and retained inventory.
  let data = writer.data
  if data == nil: return refused[StorageDurability](FullPagedNativeError.Uninitialized)
  prepare(data, candidate, root, roots, producer, count, payload, false)
proc commitGuard(data: WriterData, artifact: CandidateData): proc(): FileError {.closure.} =
  ## Capture stable exact source/target owners for the final post-staging, pre-rename identity check.
  proc beforeRename(): FileError {.closure.} =
    ## No stale manifest or replaced file gains selection authority after target synchronization.
    let source = if artifact.initial: data.directory.initialAbsent else: current(data)
    if source != FileError.None: return source
    artifact.file.check
  beforeRename
proc publish*(writer: var FullPagedWriter, candidate: var FullPagedCandidate): FullPagedNativeResult[
    FullPagedPublication] =
  ## Revalidate complete source/target and exact incarnation before atomic file/directory-synchronized selection.
  let data = writer.data
  let artifact = candidate.data
  if data == nil or artifact == nil: return refused[FullPagedPublication](
      FullPagedNativeError.Uninitialized)
  if not data.active or not artifact.active or not artifact.sealed:
    return refused[FullPagedPublication](FullPagedNativeError.InvalidCandidate)
  if artifact.owner != data: return refused[FullPagedPublication](FullPagedNativeError.StaleView)
  if data.poisoned and not artifact.initial:
    return refused[FullPagedPublication](FullPagedNativeError.RecoveryRequired)
  if artifact.initial:
    # Bootstrap has authority only over a genuinely absent selection in its exclusively owned namespace.
    let absent = data.directory.initialAbsent
    if absent != FileError.None: return fileFailed[FullPagedPublication](absent)
  else:
    let captured = artifact.source.bytes
    let selected = data.checked.manifest.bytes
    if captured.error != FullPagedError.None: return codecFailed[FullPagedPublication](captured.error)
    if selected.error != FullPagedError.None: return codecFailed[FullPagedPublication](selected.error)
    if captured.value != selected.value: return refused[FullPagedPublication](
        FullPagedNativeError.StaleView)
    let source = validateHead(data)
    if source.error != FullPagedNativeError.None: return rejected[FullPagedPublication, bool](source)
  if not data.directory.sameDirectory(artifact.file):
    return refused[FullPagedPublication](FullPagedNativeError.StaleView)
  let target = artifact.file.validateFullFile(data.directory, artifact.checked.header,
    artifact.checked.manifest, data.config.limits)
  if target.error != FileError.None: return fileFailed[FullPagedPublication](target.error)
  if target.value.error != FullPagedStreamError.None:
    return graphFailed[FullPagedPublication, CheckedFullPagedArtifact](target.value)
  let raw = artifact.checked.manifest.bytes
  if raw.error != FullPagedError.None: return codecFailed[FullPagedPublication](raw.error)
  let guarded = if artifact.initial: data.directory.initialAbsent else: current(data)
  if guarded != FileError.None: return fileFailed[FullPagedPublication](guarded)
  let identity = artifact.file.fileIdentity
  if identity.error != FileError.None: return fileFailed[FullPagedPublication](identity.error)
  let selected = replaceFullCurrent(data.directory, raw.value, commitGuard(data, artifact))
  if selected != FileError.None:
    # A failed native staging/rename/barrier cannot claim the new root; close/reopen resolves uncertainty.
    if selected != FileError.AlreadyExists: data.poisoned = true
    return fileFailed[FullPagedPublication](selected)
  data.checked = artifact.checked
  data.config.root = artifact.checked.header.root
  data.selected = true
  data.poisoned = false
  var retirement = candidate.close
  if data.head.opened:
    # Confirmed selection is irreversible; later old/new descriptor errors belong in the passive receipt.
    let retired = data.head.close
    if retirement == FileError.None: retirement = retired
  let adopted = openEpoch(data.head, data.directory, data.checked.manifest.epoch,
    PagedPin.Shared, data.config.limits.dataset.bytes)
  if adopted != FileError.None and retirement == FileError.None: retirement = adopted
  if adopted == FileError.None:
    # Shared adoption must refer to the exact previously validated target inode/version, not a substituted name.
    let held = data.head.fileIdentity
    if held.error != FileError.None:
      if retirement == FileError.None: retirement = held.error
    elif not identity.value.matches(held.value):
      if retirement == FileError.None: retirement = FileError.RecoveryMismatch
  if retirement != FileError.None: data.poisoned = true
  FullPagedNativeResult[FullPagedPublication](status: FullPagedNativeError.None,
    completed: FullPagedPublication(ready: true, selected: data.checked.manifest,
      retirement: retirement, usable: not data.poisoned))
proc initializeFullPagedWriter*(writer: var FullPagedWriter, path: string,
    config: FullPagedNativeConfig, roots: openArray[FullPagedRoot], producer: nil FullPagedProducer,
    count, payload: uint64): FullPagedNativeResult[FullPagedPublication] =
  ## Epoch-one/generation-zero bootstrap never scans, guesses or overwrites an existing database selection.
  if writer.opened: return fileFailed[FullPagedPublication](FileError.Busy)
  if producer == nil: return refused[FullPagedPublication](FullPagedNativeError.Uninitialized)
  let header = initFullPagedHeader(config.chain, config.root, ManagedEpoch(1),
    RepositoryGeneration(0), count, payload, roots, config.limits.dataset)
  if header.error != FullPagedError.None: return codecFailed[FullPagedPublication](header.error)
  let data = WriterData(config: config, poisoned: true)
  let acquired = openDirectory(data.directory, path, true, true)
  if acquired != FileError.None:
    # Even a partially acquired bootstrap lease is retired explicitly before exposing failure.
    if data.directory.opened and data.directory.close != FileError.None:
      return fileFailed[FullPagedPublication](FileError.IoFailure)
    return fileFailed[FullPagedPublication](acquired)
  data.active = true
  writer.data = data
  var candidate = default(FullPagedCandidate)
  defer:
    # Acquired failed bootstrap leaves its writer lease visible for explicit caller close.
    if candidate.opened and candidate.close != FileError.None:
      result = fileFailed[FullPagedPublication](FileError.IoFailure)
  let prepared = prepare(data, candidate, config.root, roots, producer, count, payload, true)
  if prepared.error != FullPagedNativeError.None: return rejected[FullPagedPublication,
      StorageDurability](prepared)
  writer.publish(candidate)

proc epochReceipt*(reader: FullPagedReader): FullPagedNativeResult[FullPagedEpochReceipt] =
  ## Capture exact checked epoch/namespace/version while pinned, without retaining the reader or native owner.
  let data = reader.data
  if data == nil or not data.active:
    return refused[FullPagedEpochReceipt](FullPagedNativeError.Uninitialized)
  let identity = data.file.fileIdentity
  if identity.error != FileError.None: return fileFailed[FullPagedEpochReceipt](identity.error)
  FullPagedNativeResult[FullPagedEpochReceipt](status: FullPagedNativeError.None,
    completed: FullPagedEpochReceipt(ready: true, header: data.checked.header,
      selected: data.checked.manifest, identity: identity.value, limits: data.checked.limits))
func alreadyAbsent*(receipt: FullPagedReclamation): bool {.requires: receipt.ready.} =
  ## Idempotent synchronized absence is distinct from unlinking a captured old inode during this call.
  receipt.absentBefore
func retirementError*(receipt: FullPagedReclamation): FileError {.requires: receipt.ready.} =
  ## A confirmed unlink/directory barrier is not erased by later descriptor retirement failure.
  receipt.retirement
func durability*(receipt: FullPagedReclamation): StorageDurability {.requires: receipt.ready.} =
  ## Successful already-absent retries also perform an actual directory synchronization.
  StorageDurability.FileAndDirectorySynced
func policy(limits: FullPagedStreamLimits): array[15, uint64] =
  ## Bind every dataset/trie/history/cache/workspace/scratch/work scalar exactly, including zero allowances.
  [uint64(limits.dataset.entries), uint64(limits.dataset.bytes), uint64(limits.trie.items),
    uint64(limits.trie.nodes), uint64(limits.trie.perValue), uint64(limits.trie.totalValueBytes),
    uint64(limits.roots), uint64(limits.cachePages), uint64(limits.workingBytes),
    uint64(limits.scratchBytes), uint64(limits.work.ioCalls), uint64(limits.work.hashes),
    uint64(limits.work.visits), uint64(limits.work.readBytes), uint64(limits.work.writeBytes)]
proc reclaim*(writer: var FullPagedWriter, receipt: FullPagedEpochReceipt,
    expected: FullPagedManifest): FullPagedNativeResult[FullPagedReclamation] =
  ## Delete only an exact captured older physical epoch after full source/old-graph checks and exclusive pinning.
  let data = writer.data
  if data == nil or not data.active:
    return refused[FullPagedReclamation](FullPagedNativeError.Uninitialized)
  if data.poisoned: return refused[FullPagedReclamation](FullPagedNativeError.RecoveryRequired)
  if not receipt.ready or not expected.initialized:
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  let selected = data.checked.manifest.bytes
  let captured = expected.bytes
  if selected.error != FullPagedError.None: return codecFailed[FullPagedReclamation](selected.error)
  if captured.error != FullPagedError.None: return codecFailed[FullPagedReclamation](captured.error)
  if selected.value != captured.value: return refused[FullPagedReclamation](
      FullPagedNativeError.StaleView)
  if uint64(receipt.selected.epoch) >= uint64(expected.epoch):
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  let sameChain = array[32, byte](receipt.header.chainId) == array[32, byte](data.config.chain)
  let samePolicy = policy(receipt.limits) == policy(data.config.limits)
  if not sameChain or not samePolicy or not data.directory.matchesDirectory(receipt.identity):
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  let source = validateHead(data)
  if source.error != FullPagedNativeError.None: return rejected[FullPagedReclamation, bool](source)
  let pending = data.directory.pendingAbsent
  if pending != FileError.None: return fileFailed[FullPagedReclamation](pending)
  let exists = data.directory.epochExists(receipt.selected.epoch)
  if exists.error != FileError.None: return fileFailed[FullPagedReclamation](exists.error)
  if not exists.value:
    # Fresh source checking and a real barrier qualify idempotent absence; stale names never become an unlink wildcard.
    let current = current(data)
    if current != FileError.None: return fileFailed[FullPagedReclamation](current)
    let confirmed = data.directory.synchronize
    if confirmed != FileError.None:
      data.poisoned = true
      return fileFailed[FullPagedReclamation](confirmed)
    return FullPagedNativeResult[FullPagedReclamation](status: FullPagedNativeError.None,
      completed: FullPagedReclamation(ready: true, absentBefore: true, retirement: FileError.None))
  var file = default(PagedFile)
  defer:
    # Pre-confirmation failure may not leak even a captured exclusive cleanup pin.
    if file.opened and file.close != FileError.None:
      result = fileFailed[FullPagedReclamation](FileError.IoFailure)
  let pinned = openEpoch(file, data.directory, receipt.selected.epoch,
    PagedPin.Exclusive, receipt.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[FullPagedReclamation](pinned)
  let actual = file.fileIdentity
  if actual.error != FileError.None: return fileFailed[FullPagedReclamation](actual.error)
  if not receipt.identity.matches(actual.value):
    return fileFailed[FullPagedReclamation](FileError.RecoveryMismatch)
  let verified = file.validateFullFile(data.directory, receipt.header, receipt.selected,
      receipt.limits)
  if verified.error != FileError.None: return fileFailed[FullPagedReclamation](verified.error)
  if verified.value.error != FullPagedStreamError.None:
    return graphFailed[FullPagedReclamation, CheckedFullPagedArtifact](verified.value)
  let current = current(data)
  if current != FileError.None: return fileFailed[FullPagedReclamation](current)
  let removed = removePinned(data.directory, file)
  if removed != FileError.None:
    data.poisoned = true
    return fileFailed[FullPagedReclamation](removed)
  let retired = file.close
  FullPagedNativeResult[FullPagedReclamation](status: FullPagedNativeError.None,
    completed: FullPagedReclamation(ready: true, absentBefore: false, retirement: retired))
