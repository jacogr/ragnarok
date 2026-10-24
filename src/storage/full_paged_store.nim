# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Durable full-state paged writers, sealed candidates and readers require complete graph admission.
## Explicit close exposes retirement uncertainty; no reader owns a writer lease, callback or resident graph.
## One caller serializes operations per owner; independent readers have independent native seek cursors.
import std/assertions
import ./[full_paged_codec, full_paged_stream, paged_io, paged_codec, database_identity,
  file_errors, full_paged_build, durability,
  managed_manifest, node_repository, paged_stream]
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
    replayBytes*: ByteLimit ## Explicit anonymous replay disk ceiling; zero denies replay cleanup.
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
    file, pending: PagedFile
    owner: WriterData
    checked: CheckedFullPagedArtifact
    source: FullPagedManifest
    active, sealed, initial, recovery: bool
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
proc openReader(reader: var FullPagedReader, path: string, config: FullPagedNativeConfig,
    expected: FullPagedManifest, explicitEpoch: bool): FullPagedNativeResult[bool] =
  ## One shared-pin admission path binds either exact CURRENT or an independently supplied complete epoch manifest.
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
  var selection: seq[byte] = @[]
  if explicitEpoch:
    # Caller-known immutable manifest/root authority never follows disk-discovered history or CURRENT.
    let encoded = expected.bytes
    if encoded.error != FullPagedError.None: return codecFailed[bool](encoded.error)
    for octet in encoded.value: selection.add(octet) # Exactly192 bytes, independent of dataset extent.
  else:
    # Ordinary startup captures the current selected bytes before acquiring its independent shared pin.
    let current = directory.readFullCurrent
    if current.error != FileError.None: return fileFailed[bool](current.error)
    selection = current.value
  let selected = decodeFullPagedSelection(selection, config.chain, config.root,
      config.limits.dataset, uint64(config.limits.contextBytes) > 0)
  if selected.error != FullPagedError.None: return codecFailed[bool](selected.error)
  let pinned = openEpoch(file, directory, selected.value.epoch, PagedPin.Shared,
      config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[bool](pinned)
  let header = file.readFullHeader(config.chain, config.root, config.limits.dataset,
      config.limits.contextBytes)
  if header.error != FileError.None: return fileFailed[bool](header.error)
  if header.value.error != FullPagedError.None: return codecFailed[bool](header.value.error)
  let binding = decodeFullPagedManifest(selection, header.value.value)
  if binding.error != FullPagedError.None: return codecFailed[bool](binding.error)
  let admitted = file.validateFullFile(directory, header.value.value, selected.value, config.limits)
  if admitted.error != FileError.None: return fileFailed[bool](admitted.error)
  if admitted.value.error != FullPagedStreamError.None: return graphFailed[bool,
      CheckedFullPagedArtifact](admitted.value)
  if not explicitEpoch:
    # Only current-selection readers need this race check; explicit old manifests stay bound to their pinned immutable file.
    let again = directory.readFullCurrent
    if again.error != FileError.None: return fileFailed[bool](again.error)
    if selection != again.value: return fileFailed[bool](FileError.StaleView)
  let checked = file.check
  if checked != FileError.None: return fileFailed[bool](checked)
  let retired = directory.close
  if retired != FileError.None: return fileFailed[bool](retired)
  reader.data = ReaderData(file: move(file), checked: admitted.value.value, active: true)
  FullPagedNativeResult[bool](status: FullPagedNativeError.None, completed: true)
proc openFullPagedReader*(reader: var FullPagedReader, path: string,
    config: FullPagedNativeConfig): FullPagedNativeResult[bool] =
  ## Strict CURRENT startup uses an independent shared pin, complete graph admission and exact selection reread.
  openReader(reader, path, config, default(FullPagedManifest), false)
proc openFullPagedEpochReader*(reader: var FullPagedReader, path: string,
    config: FullPagedNativeConfig, expected: FullPagedManifest): FullPagedNativeResult[bool] =
  ## Reopen one independently known immutable epoch after restart; no directory scan or inferred historical root is allowed.
  openReader(reader, path, config, expected, true)
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
  var reason = FileError.None
  if data.file.opened: reason = data.file.close
  if data.pending.opened:
    # Retire staging even when the independent epoch close reports uncertainty.
    let retired = data.pending.close
    if reason == FileError.None: reason = retired
  reason
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
proc acquireWriter(writer: var FullPagedWriter, path: string,
    config: FullPagedNativeConfig, local: bool): FullPagedNativeResult[bool] =
  ## One lease guards exact CURRENT/header/complete-graph admission; local context and independent imports remain explicit separate entry points.
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
  var expected = config
  if local:
    # Contextual local recovery may discover its posterior root only under the acquired stable lease.
    # This metadata remains untrusted until complete selection/header/graph and application context checks succeed.
    if uint64(config.limits.contextBytes) == 0:
      return FullPagedNativeResult[bool](status: FullPagedNativeError.GraphFailure,
          graphCause: FullPagedStreamError.UnsupportedPolicy)
    if current.value.len != FullPagedManifestBytes: return codecFailed[bool](
        FullPagedError.InvalidFormat)
    var root = default(array[32, byte])
    for index in 0..<32: root[index] = current.value[64+index] # Exact fixed extent was checked before access.
    expected.root = StateRoot(root)
  let selected = decodeFullPagedSelection(current.value, expected.chain, expected.root,
      expected.limits.dataset, uint64(expected.limits.contextBytes) > 0)
  if selected.error != FullPagedError.None: return codecFailed[bool](selected.error)
  let pinned = openEpoch(data.head, data.directory, selected.value.epoch,
    PagedPin.Shared, config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[bool](pinned)
  let header = data.head.readFullHeader(expected.chain, expected.root, config.limits.dataset,
      config.limits.contextBytes)
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
  data.config = expected
  data.checked = admitted.value.value
  data.active = true
  data.selected = true
  writer.data = data
  FullPagedNativeResult[bool](status: FullPagedNativeError.None, completed: true)
proc openFullPagedWriter*(writer: var FullPagedWriter, path: string,
    config: FullPagedNativeConfig): FullPagedNativeResult[bool] =
  ## Independent root selection remains mandatory for external import or explicitly expected storage opens.
  acquireWriter(writer, path, config, false)
proc openLocalFullPagedWriter*(writer: var FullPagedWriter, path: string, chain: StorageChainId,
    limits: FullPagedStreamLimits, construction: FullPagedConstructionLimits,
    replayBytes: ByteLimit): FullPagedNativeResult[bool] =
  ## Recover one V2 local complete graph under its exclusive lease; callers must still bind context/profile/history before adoption.
  acquireWriter(writer, path, FullPagedNativeConfig(chain: chain, limits: limits,
    construction: construction, replayBytes: replayBytes), true)
func buildLimits(config: FullPagedNativeConfig): FullPagedBuildLimits =
  ## Inherited admission policy cannot be substituted by a separate construction-budget object.
  let work = config.construction
  FullPagedBuildLimits(admission: config.limits, producerCalls: work.producerCalls,
    ioCalls: work.ioCalls, hashes: work.hashes, readBytes: work.readBytes,
    writeBytes: work.writeBytes)
proc prepare(data: WriterData, candidate: var FullPagedCandidate, root: StateRoot,
    roots: openArray[FullPagedRoot], producer: nil FullPagedProducer, count, payload: uint64,
    initial: bool, compaction = false, context: openArray[byte] = []): FullPagedNativeResult[
        StorageDurability] =
  ## Exact predecessor and writer incarnation bind each sealed complete target to one live publication authority.
  if candidate.opened: return fileFailed[StorageDurability](FileError.Busy)
  if not data.active or (producer == nil and not compaction): return refused[StorageDurability](
      FullPagedNativeError.Uninitialized)
  if data.poisoned and not initial: return refused[StorageDurability](
      FullPagedNativeError.RecoveryRequired)
  var epoch = 1'u64
  var generation = 0'u64
  var source = default(FullPagedManifest)
  if not initial:
    # Replacement advances generation; exact compaction preserves even its maximum while advancing physical epoch.
    let header = data.checked.header
    if uint64(header.epoch) == high(uint64) or
        (not compaction and uint64(header.generation) == high(uint64)):
      return refused[StorageDurability](FullPagedNativeError.CounterExhausted)
    epoch = uint64(header.epoch)+1
    generation = uint64(header.generation)
    if not compaction: inc generation
    let checked = validateHead(data)
    if checked.error != FullPagedNativeError.None: return rejected[StorageDurability, bool](checked)
    source = data.checked.manifest
  let contextSize = if compaction: data.checked.header.geometry.contextBytes else: uint64(context.len)
  let contextPolicy = validateFullPagedContextSize(contextSize, data.config.limits.contextBytes)
  if contextPolicy != FullPagedStreamError.None:
    return FullPagedNativeResult[StorageDurability](status: FullPagedNativeError.GraphFailure,
      graphCause: contextPolicy, graphCodec: FullPagedError.Uninitialized) # Refuse before acquiring any candidate file.
  let header = initFullPagedHeader(data.config.chain, root, ManagedEpoch(epoch),
    RepositoryGeneration(generation), count, payload, roots, data.config.limits.dataset, contextSize)
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
  if not compaction and (count >= high(uint64) div 2 or (count+1)*2 > uint64(limits.producerCalls)):
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
  let authored = if compaction:
    compactFullFile(artifact.file, data.head, data.directory, data.checked, header.value,
      FullPagedCompactionLimits(ioCalls: limits.ioCalls, hashes: limits.hashes,
        readBytes: limits.readBytes, writeBytes: limits.writeBytes))
  else:
    buildFullFile(artifact.file, data.directory, producer, header.value, limits, context)
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
    count, payload: uint64, context: openArray[byte] = []): FullPagedNativeResult[
        StorageDurability] =
  ## Explicit complete replacement chooses an independently expected target root and retained inventory.
  let data = writer.data
  if data == nil: return refused[StorageDurability](FullPagedNativeError.Uninitialized)
  prepare(data, candidate, root, roots, producer, count, payload, false, context = context)
proc prepareFullPagedCompaction*(writer: var FullPagedWriter,
    candidate: var FullPagedCandidate): FullPagedNativeResult[StorageDurability] =
  ## Full root union, ordinary generation and physical bytes derive only from the held checked source.
  let data = writer.data
  if data == nil or not data.active: return refused[StorageDurability](
      FullPagedNativeError.Uninitialized)
  if data.poisoned or not data.selected: return refused[StorageDurability](
      FullPagedNativeError.RecoveryRequired)
  let source = data.checked.header
  var roots = default(array[FullPagedMaxRoots, FullPagedRoot])
  for index in 0..<source.len:
    # The header already bounds the complete inventory to64 scalar claims.
    roots[index] = source.retainedRoot(index)
  prepare(data, candidate, source.root, roots.toOpenArray(0, source.len-1), nil,
    source.geometry.entries, source.geometry.payloadBytes, false, true)
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
    count, payload: uint64, context: openArray[byte] = []): FullPagedNativeResult[
        FullPagedPublication] =
  ## Epoch-one/generation-zero bootstrap never scans, guesses or overwrites an existing database selection.
  if writer.opened: return fileFailed[FullPagedPublication](FileError.Busy)
  if producer == nil: return refused[FullPagedPublication](FullPagedNativeError.Uninitialized)
  let contextPolicy = validateFullPagedContextSize(uint64(context.len), config.limits.contextBytes)
  if contextPolicy != FullPagedStreamError.None:
    return FullPagedNativeResult[FullPagedPublication](status: FullPagedNativeError.GraphFailure,
      graphCause: contextPolicy, graphCodec: FullPagedError.Uninitialized) # No unsupported-format bootstrap creates forensic files.
  let header = initFullPagedHeader(config.chain, config.root, ManagedEpoch(1),
    RepositoryGeneration(0), count, payload, roots, config.limits.dataset, uint64(context.len))
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
  let prepared = prepare(data, candidate, config.root, roots, producer, count, payload, true,
      context = context)
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
func policy(limits: FullPagedStreamLimits): array[16, uint64] =
  ## Bind every dataset/trie/history/cache/workspace/scratch/work scalar exactly, including zero allowances.
  [uint64(limits.dataset.entries), uint64(limits.dataset.bytes), uint64(limits.trie.items),
    uint64(limits.trie.nodes), uint64(limits.trie.perValue), uint64(limits.trie.totalValueBytes),
    uint64(limits.roots), uint64(limits.cachePages), uint64(limits.workingBytes),
    uint64(limits.scratchBytes), uint64(limits.work.ioCalls), uint64(limits.work.hashes),
    uint64(limits.work.visits), uint64(limits.work.readBytes), uint64(limits.work.writeBytes),
    uint64(limits.contextBytes)]
proc reclaimEpoch(writer: var FullPagedWriter, previous, expected: FullPagedManifest,
    receipt: FullPagedEpochReceipt, capturedIdentity: bool): FullPagedNativeResult[
        FullPagedReclamation] =
  ## Shared bounded deletion checks exact expected old content; captured receipts additionally bind the original inode.
  let data = writer.data
  if data == nil or not data.active:
    return refused[FullPagedReclamation](FullPagedNativeError.Uninitialized)
  if data.poisoned: return refused[FullPagedReclamation](FullPagedNativeError.RecoveryRequired)
  if not previous.initialized or not expected.initialized:
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  let selected = data.checked.manifest.bytes
  let captured = expected.bytes
  if selected.error != FullPagedError.None: return codecFailed[FullPagedReclamation](selected.error)
  if captured.error != FullPagedError.None: return codecFailed[FullPagedReclamation](captured.error)
  if selected.value != captured.value: return refused[FullPagedReclamation](
      FullPagedNativeError.StaleView)
  let oldBytes = previous.bytes
  if oldBytes.error != FullPagedError.None: return codecFailed[FullPagedReclamation](oldBytes.error)
  let oldSelection = decodeFullPagedSelection(oldBytes.value, data.config.chain, previous.root,
    data.config.limits.dataset, uint64(data.config.limits.contextBytes) > 0)
  if oldSelection.error != FullPagedError.None:
    return codecFailed[FullPagedReclamation](oldSelection.error)
  if uint64(previous.epoch) >= uint64(expected.epoch):
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  if uint64(previous.generation) > uint64(expected.generation):
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  if capturedIdentity:
    # Original receipt authority remains bound to its namespace, policy, chain and captured inode.
    if not receipt.ready: return refused[FullPagedReclamation](
        FullPagedNativeError.InvalidCandidate)
    let sameChain = array[32, byte](receipt.header.chainId) == array[32, byte](data.config.chain)
    let samePolicy = policy(receipt.limits) == policy(data.config.limits)
    if not sameChain or not samePolicy or not data.directory.matchesDirectory(receipt.identity):
      return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  let source = validateHead(data)
  if source.error != FullPagedNativeError.None: return rejected[FullPagedReclamation, bool](source)
  let pending = data.directory.pendingAbsent
  if pending != FileError.None: return fileFailed[FullPagedReclamation](pending)
  let exists = data.directory.epochExists(previous.epoch)
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
  let pinned = openEpoch(file, data.directory, previous.epoch,
    PagedPin.Exclusive, data.config.limits.dataset.bytes)
  if pinned != FileError.None: return fileFailed[FullPagedReclamation](pinned)
  if capturedIdentity:
    # A byte-identical replacement inode still cannot satisfy an original captured-inode receipt.
    let actual = file.fileIdentity
    if actual.error != FileError.None: return fileFailed[FullPagedReclamation](actual.error)
    if not receipt.identity.matches(actual.value):
      return fileFailed[FullPagedReclamation](FileError.RecoveryMismatch)
  let header = file.readFullHeader(data.config.chain, previous.root, data.config.limits.dataset,
    data.config.limits.contextBytes)
  if header.error != FileError.None: return fileFailed[FullPagedReclamation](header.error)
  if header.value.error != FullPagedError.None: return codecFailed[FullPagedReclamation](
      header.value.error)
  let encoded = previous.bytes
  if encoded.error != FullPagedError.None: return codecFailed[FullPagedReclamation](encoded.error)
  let bound = decodeFullPagedManifest(encoded.value, header.value.value)
  if bound.error != FullPagedError.None: return codecFailed[FullPagedReclamation](bound.error)
  let verified = file.validateFullFile(data.directory, header.value.value, previous,
    data.config.limits)
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

proc reclaim*(writer: var FullPagedWriter, receipt: FullPagedEpochReceipt,
    expected: FullPagedManifest): FullPagedNativeResult[FullPagedReclamation] =
  ## Captured reader authority requires the exact original inode even after all owning readers retire.
  if not receipt.ready: return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  reclaimEpoch(writer, receipt.selected, expected, receipt, true)
proc reclaimExpectedEpoch*(writer: var FullPagedWriter, previous,
    expected: FullPagedManifest): FullPagedNativeResult[FullPagedReclamation] =
  ## An independently authenticated old manifest authorizes exact content, not an inode remembered before restart.
  ## Never derive previous from a namespace scan. Complete admission, an exclusive pin and current fencing precede unlink.
  reclaimEpoch(writer, previous, expected, default(FullPagedEpochReceipt), false)

proc sameManifest(left, right: FullPagedManifest): bool =
  ## Defaults cannot compare equal as source authority; codec failure never grants byte equality.
  if not left.initialized or not right.initialized: return false
  let a = left.bytes
  let b = right.bytes
  a.error == FullPagedError.None and b.error == FullPagedError.None and a.value == b.value
func comparisonLimits(config: FullPagedNativeConfig): PagedWorkLimits =
  ## Each fixed-page comparison has explicit finite IO/read ceilings, separate from graph admission.
  PagedWorkLimits(ioCalls: config.construction.ioCalls, readBytes: config.construction.readBytes)
proc prepareCleanup(data: WriterData, candidate: var FullPagedCandidate,
    expectedSource: FullPagedManifest, target: FullPagedHeader,
    producer: nil FullPagedProducer, initial: bool, context: openArray[byte] = []): FullPagedNativeResult[bool] =
  ## Reproduce and fully admit exact target bytes in bounded anonymous disk scratch before granting cleanup authority.
  if not data.active: return refused[bool](FullPagedNativeError.Uninitialized)
  if data.poisoned and not initial: return refused[bool](FullPagedNativeError.RecoveryRequired)
  if candidate.opened: return fileFailed[bool](FileError.Busy)
  if not target.initialized: return refused[bool](FullPagedNativeError.InvalidCandidate)
  if array[32, byte](target.chainId) != array[32, byte](data.config.chain):
    return refused[bool](FullPagedNativeError.InvalidCandidate)
  var source = default(FullPagedManifest)
  var compaction = false
  if initial:
    # Bootstrap authority requires independent root/position and actual CURRENT absence under the existing lease.
    if data.selected or expectedSource.initialized:
      return refused[bool](FullPagedNativeError.InvalidCandidate)
    let absent = data.directory.initialAbsent
    if absent != FileError.None: return fileFailed[bool](absent)
    let sameRoot = array[32, byte](target.root) == array[32, byte](data.config.root)
    if not sameRoot or uint64(target.epoch) != 1 or uint64(target.generation) != 0:
      return refused[bool](FullPagedNativeError.InvalidCandidate)
  else:
    # Existing recovery binds an exact predecessor; same-generation targets are exclusively source-derived compactions.
    source = data.checked.manifest
    if not sameManifest(expectedSource, source): return refused[bool](
        FullPagedNativeError.StaleView)
    if uint64(source.epoch) == high(uint64): return refused[bool](
        FullPagedNativeError.CounterExhausted)
    if uint64(target.epoch) != uint64(source.epoch)+1:
      return refused[bool](FullPagedNativeError.InvalidCandidate)
    compaction = uint64(target.generation) == uint64(source.generation)
    if not compaction:
      # Ordinary replacement advances once; comparison precedes addition at the maximum generation.
      if uint64(source.generation) == high(uint64):
        return refused[bool](FullPagedNativeError.CounterExhausted)
      if uint64(target.generation) != uint64(source.generation)+1:
        return refused[bool](FullPagedNativeError.InvalidCandidate)
    let head = validateHead(data)
    if head.error != FullPagedNativeError.None: return rejected[bool, bool](head)
  if not compaction and producer == nil: return refused[bool](FullPagedNativeError.InvalidCandidate)
  let shape = target.geometry
  let contextPolicy = validateFullPagedContextSize(shape.contextBytes,
      data.config.limits.contextBytes)
  if contextPolicy != FullPagedStreamError.None:
    return FullPagedNativeResult[bool](status: FullPagedNativeError.GraphFailure,
      graphCause: contextPolicy, graphCodec: FullPagedError.Uninitialized) # Replay must match the inherited physical format and quota.
  if (compaction and context.len != 0) or (not compaction and uint64(context.len) !=
      shape.contextBytes):
    return refused[bool](FullPagedNativeError.InvalidCandidate) # Compaction derives bytes; replacement requires the exact independent replay input.
  let bounded = pagedGeometry(shape.entries, shape.payloadBytes, data.config.limits.dataset,
      shape.contextBytes)
  if bounded.error != PagedCodecError.None: return fileFailed[bool](FileError.LimitExceeded)
  if shape.byteLength > uint64(data.config.replayBytes): return fileFailed[bool](
      FileError.LimitExceeded)
  var scratch = default(PagedFile)
  defer:
    # Anonymous replay close uncertainty prevents capturing a successful cleanup capability.
    if scratch.opened and scratch.close != FileError.None: result = fileFailed[bool](
        FileError.IoFailure)
  let acquired = openScratch(scratch, data.directory, data.config.replayBytes)
  if acquired != FileError.None: return fileFailed[bool](acquired)
  let limits = buildLimits(data.config)
  let authored = if compaction:
    compactFullFile(scratch, data.head, data.directory, data.checked, target,
      FullPagedCompactionLimits(ioCalls: limits.ioCalls, hashes: limits.hashes,
        readBytes: limits.readBytes, writeBytes: limits.writeBytes))
  else:
    buildFullFile(scratch, data.directory, producer, target, limits, context)
  if authored.error != FileError.None: return fileFailed[bool](authored.error)
  if authored.value.error != FullPagedBuildError.None: return buildFailed[bool](authored.value)
  let built = authored.value.value.checked
  let manifest = built.manifest.bytes
  if manifest.error != FullPagedError.None: return codecFailed[bool](manifest.error)
  let artifact = CandidateData(owner: data, source: source, checked: built, recovery: true,
      initial: initial)
  defer:
    # Until adoption both independent captured resources remain local explicit-close obligations.
    if candidate.data == nil:
      if artifact.file.opened and artifact.file.close != FileError.None:
        result = fileFailed[bool](FileError.IoFailure)
      if artifact.pending.opened and artifact.pending.close != FileError.None:
        result = fileFailed[bool](FileError.IoFailure)
  let exists = data.directory.epochExists(target.epoch)
  if exists.error != FileError.None: return fileFailed[bool](exists.error)
  if exists.value:
    # An arbitrary partial epoch becomes eligible only after complete prefix equality under an exclusive pin.
    let pinned = openEpoch(artifact.file, data.directory, target.epoch,
      PagedPin.Exclusive, data.config.limits.dataset.bytes)
    if pinned != FileError.None: return fileFailed[bool](pinned)
    let matched = matchesPrefix(artifact.file, scratch, comparisonLimits(data.config))
    if matched != FileError.None: return fileFailed[bool](matched)
  let pending = openFullPending(artifact.pending, data.directory)
  if pending.error != FileError.None: return fileFailed[bool](pending.error)
  if pending.value:
    # Validate staging before either child can be removed; light-width or overlong files refuse.
    let matched = matchesFullPrefix(artifact.pending, manifest.value, comparisonLimits(data.config))
    if matched != FileError.None: return fileFailed[bool](matched)
  let current = if initial: data.directory.initialAbsent else: current(data)
  if current != FileError.None: return fileFailed[bool](current)
  let retired = scratch.close
  if retired != FileError.None: return fileFailed[bool](retired)
  artifact.active = true
  candidate.data = artifact
  FullPagedNativeResult[bool](status: FullPagedNativeError.None, completed: true)
proc prepareFullPagedCleanup*(writer: var FullPagedWriter, candidate: var FullPagedCandidate,
    expectedSource: FullPagedManifest, target: FullPagedHeader,
    producer: nil FullPagedProducer, context: openArray[byte] = []): FullPagedNativeResult[bool] =
  ## Explicit independently expected replacement or source-derived compaction never scans for cleanup targets.
  let data = writer.data
  if data == nil: return refused[bool](FullPagedNativeError.Uninitialized)
  prepareCleanup(data, candidate, expectedSource, target, producer, false, context)
proc discardFullPagedCandidate*(writer: var FullPagedWriter, candidate: var FullPagedCandidate,
    expectedSource: FullPagedManifest): FullPagedNativeResult[FullPagedReclamation] =
  ## Every source, epoch and staging preflight must pass before unlink; uncertainty poisons the writer.
  let data = writer.data
  let artifact = candidate.data
  if data == nil or artifact == nil: return refused[FullPagedReclamation](
      FullPagedNativeError.Uninitialized)
  if not data.active or not artifact.active:
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  if artifact.owner != data: return refused[FullPagedReclamation](FullPagedNativeError.StaleView)
  if artifact.initial and (not artifact.recovery or data.selected):
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  if data.poisoned and not artifact.initial:
    return refused[FullPagedReclamation](FullPagedNativeError.RecoveryRequired)
  if artifact.initial:
    # A bootstrap cleanup capability cannot overwrite or remove any selected CURRENT, even malformed bytes.
    if expectedSource.initialized or artifact.source.initialized:
      return refused[FullPagedReclamation](FullPagedNativeError.StaleView)
    let absent = data.directory.initialAbsent
    if absent != FileError.None: return fileFailed[FullPagedReclamation](absent)
  else:
    # A detached source receipt cannot follow a newer selection or revive another writer incarnation.
    if not sameManifest(expectedSource, artifact.source):
      return refused[FullPagedReclamation](FullPagedNativeError.StaleView)
    if not sameManifest(expectedSource, data.checked.manifest):
      return refused[FullPagedReclamation](FullPagedNativeError.StaleView)
    let head = validateHead(data)
    if head.error != FullPagedNativeError.None: return rejected[FullPagedReclamation, bool](head)
  if not artifact.sealed and not artifact.recovery:
    return refused[FullPagedReclamation](FullPagedNativeError.InvalidCandidate)
  let absent = not artifact.file.opened
  if not absent:
    # Captured namespace/inode/version/extent must still match before any destructive namespace operation.
    if not data.directory.sameDirectory(artifact.file):
      return refused[FullPagedReclamation](FullPagedNativeError.StaleView)
    let checked = artifact.file.check
    if checked != FileError.None: return fileFailed[FullPagedReclamation](checked)
    if artifact.sealed:
      # A live complete seal supplies direct full-graph validation without a new producer replay.
      let verified = artifact.file.validateFullFile(data.directory, artifact.checked.header,
        artifact.checked.manifest, data.config.limits)
      if verified.error != FileError.None: return fileFailed[FullPagedReclamation](verified.error)
      if verified.value.error != FullPagedStreamError.None:
        return graphFailed[FullPagedReclamation, CheckedFullPagedArtifact](verified.value)
  else:
    # Captured absence cannot authorize a file that appeared after replay preparation.
    let exists = data.directory.epochExists(artifact.checked.manifest.epoch)
    if exists.error != FileError.None: return fileFailed[FullPagedReclamation](exists.error)
    if exists.value: return refused[FullPagedReclamation](FullPagedNativeError.StaleView)
  let manifest = artifact.checked.manifest.bytes
  if manifest.error != FullPagedError.None: return codecFailed[FullPagedReclamation](manifest.error)
  if artifact.sealed and not artifact.pending.opened:
    # Live seals may capture staging lazily; every subsequent attempt still rechecks its exact prefix.
    let pending = openFullPending(artifact.pending, data.directory)
    if pending.error != FileError.None: return fileFailed[FullPagedReclamation](pending.error)
  if artifact.pending.opened:
    # Failed prefix validation never becomes implicit permission on a retry.
    let checked = matchesFullPrefix(artifact.pending, manifest.value, comparisonLimits(data.config))
    if checked != FileError.None: return fileFailed[FullPagedReclamation](checked)
  else:
    # Prepared staging absence refuses any later-created unknown child.
    let checked = data.directory.pendingAbsent
    if checked != FileError.None: return fileFailed[FullPagedReclamation](checked)
  let current = if artifact.initial: data.directory.initialAbsent else: current(data)
  if current != FileError.None: return fileFailed[FullPagedReclamation](current)
  if not absent:
    # All preflights precede the first unlink, and uncertainty requires fresh capture after reopen.
    let removed = removePinned(data.directory, artifact.file)
    if removed != FileError.None:
      data.poisoned = true
      return fileFailed[FullPagedReclamation](removed)
  if artifact.pending.opened:
    # Independently pinned staging is removed only after its own byte/version checks passed above.
    let removed = removePinned(data.directory, artifact.pending)
    if removed != FileError.None:
      data.poisoned = true
      return fileFailed[FullPagedReclamation](removed)
  let confirmed = data.directory.synchronize
  if confirmed != FileError.None:
    data.poisoned = true
    return fileFailed[FullPagedReclamation](confirmed)
  let retired = candidate.close
  FullPagedNativeResult[FullPagedReclamation](status: FullPagedNativeError.None,
    completed: FullPagedReclamation(ready: true, absentBefore: absent, retirement: retired))
proc resumeFullPagedInitialization*(writer: var FullPagedWriter, path: string,
    config: FullPagedNativeConfig, roots: openArray[FullPagedRoot], producer: nil FullPagedProducer,
    count, payload: uint64, context: openArray[byte] = []): FullPagedNativeResult[
        FullPagedPublication] =
  ## Existing LOCK and absent CURRENT permit exact replay cleanup then independently bound fresh bootstrap.
  if writer.opened: return fileFailed[FullPagedPublication](FileError.Busy)
  if producer == nil: return refused[FullPagedPublication](FullPagedNativeError.Uninitialized)
  let contextPolicy = validateFullPagedContextSize(uint64(context.len), config.limits.contextBytes)
  if contextPolicy != FullPagedStreamError.None:
    return FullPagedNativeResult[FullPagedPublication](status: FullPagedNativeError.GraphFailure,
      graphCause: contextPolicy, graphCodec: FullPagedError.Uninitialized) # No unsupported-format bootstrap creates forensic files.
  let header = initFullPagedHeader(config.chain, config.root, ManagedEpoch(1),
    RepositoryGeneration(0), count, payload, roots, config.limits.dataset, uint64(context.len))
  if header.error != FullPagedError.None: return codecFailed[FullPagedPublication](header.error)
  let data = WriterData(config: config, poisoned: true)
  let acquired = openDirectory(data.directory, path, false, true)
  if acquired != FileError.None:
    # Even partial native lease setup is retired before a failed resume returns.
    if data.directory.opened and data.directory.close != FileError.None:
      return fileFailed[FullPagedPublication](FileError.IoFailure)
    return fileFailed[FullPagedPublication](acquired)
  data.active = true
  writer.data = data
  var candidate = default(FullPagedCandidate)
  defer:
    # Acquired failures keep the writer visible but always retire local candidate descriptors.
    if candidate.opened and candidate.close != FileError.None:
      result = fileFailed[FullPagedPublication](FileError.IoFailure)
  let replayed = prepareCleanup(data, candidate, default(FullPagedManifest), header.value, producer,
      true, context)
  if replayed.error != FullPagedNativeError.None: return rejected[FullPagedPublication, bool](replayed)
  let cleanup = candidate.data
  assert cleanup != nil
  let expected = cleanup.checked.manifest
  let removed = discardFullPagedCandidate(writer, candidate, default(FullPagedManifest))
  if removed.error != FullPagedNativeError.None:
    return rejected[FullPagedPublication, FullPagedReclamation](removed)
  if removed.value.retirementError != FileError.None:
    return fileFailed[FullPagedPublication](removed.value.retirementError)
  let prepared = prepare(data, candidate, config.root, roots, producer, count, payload, true,
      context = context)
  if prepared.error != FullPagedNativeError.None:
    return rejected[FullPagedPublication, StorageDurability](prepared)
  let authored = candidate.data
  assert authored != nil
  if not sameManifest(authored.checked.manifest, expected):
    return refused[FullPagedPublication](FullPagedNativeError.InvalidCandidate)
  writer.publish(candidate)

proc rootInfo*(reader: FullPagedReader, root: StateRoot): FullPagedNativeResult[FullPagedRoot] =
  ## Return copied completely admitted counts for an independently selected retained root, without granting chain/history trust.
  let data = reader.data
  if data == nil or not data.active: return refused[FullPagedRoot](
      FullPagedNativeError.Uninitialized)
  let held = data.file.check
  if held != FileError.None: return fileFailed[FullPagedRoot](held)
  let header = data.checked.header
  for index in 0..<header.len:
    # No mutable inventory backing storage or reader retirement authority escapes this metadata lookup.
    let claim = header.retainedRoot(index)
    if array[32, byte](claim.root) == array[32, byte](root):
      return FullPagedNativeResult[FullPagedRoot](status: FullPagedNativeError.None,
          completed: claim)
  FullPagedNativeResult[FullPagedRoot](status: FullPagedNativeError.GraphFailure,
    graphCause: FullPagedStreamError.UnknownRoot, graphCodec: FullPagedError.Uninitialized)
proc visitEntries*(reader: FullPagedReader, root: StateRoot, visitor: nil FullPagedEntryVisitor,
    budget: FullPagedWorkLimits): FullPagedNativeResult[FullPagedCounts] =
  ## Borrow sorted complete-root values synchronously under this reader's immutable pin; caller stages output until full success.
  let data = reader.data
  if data == nil or not data.active: return refused[FullPagedCounts](
      FullPagedNativeError.Uninitialized)
  let streamed = data.file.streamFullEntries(data.checked, root, visitor, budget)
  if streamed.error != FullPagedStreamError.None:
    return graphFailed[FullPagedCounts, FullPagedCounts](streamed)
  FullPagedNativeResult[FullPagedCounts](status: FullPagedNativeError.None,
      completed: streamed.value)
proc visitEntries*(reader: FullPagedReader, root: StateRoot,
    visitor: nil FullPagedEntryVisitor): FullPagedNativeResult[FullPagedCounts] =
  ## Default traversal retains the originally admitted finite work policy, never an unbounded producer allowance.
  let data = reader.data
  if data == nil or not data.active: return refused[FullPagedCounts](
      FullPagedNativeError.Uninitialized)
  reader.visitEntries(root, visitor, data.checked.limits.work)

func failure*[T](outcome: FullPagedNativeResult[T]): FullPagedNativeResult[bool] {.requires:
    outcome.status != FullPagedNativeError.None.} =
  ## Composite consumers retain an exact selected failure without carrying any successful operation payload.
  rejected[bool, T](outcome)

proc readContext*(reader: FullPagedReader, budget: FullPagedWorkLimits): FullPagedNativeResult[
    FullPagedContext] =
  ## Return independently owned opaque context only from a fully admitted immutable epoch reader.
  let data = reader.data
  if data == nil or not data.active: return refused[FullPagedContext](
      FullPagedNativeError.Uninitialized)
  let captured = data.file.contextFullFile(data.checked, budget)
  if captured.error != FullPagedStreamError.None: return graphFailed[FullPagedContext,
      FullPagedContext](captured)
  FullPagedNativeResult[FullPagedContext](status: FullPagedNativeError.None,
      completed: captured.value)
proc readContext*(writer: FullPagedWriter, budget: FullPagedWorkLimits): FullPagedNativeResult[
    FullPagedContext] =
  ## Startup may inspect the already admitted selected immutable head while holding the exclusive writer lease.
  let data = writer.data
  if data == nil or not data.active or not data.selected: return refused[FullPagedContext](
      FullPagedNativeError.Uninitialized)
  if data.poisoned: return refused[FullPagedContext](FullPagedNativeError.RecoveryRequired)
  let captured = data.head.contextFullFile(data.checked, budget)
  if captured.error != FullPagedStreamError.None: return graphFailed[FullPagedContext,
      FullPagedContext](captured)
  FullPagedNativeResult[FullPagedContext](status: FullPagedNativeError.None,
      completed: captured.value)

proc rootInfo*(writer: FullPagedWriter, root: StateRoot): FullPagedNativeResult[FullPagedRoot] =
  ## Inspect completely admitted retained-root claims while holding the writer lease, without a second reader admission.
  let data = writer.data
  if data == nil or not data.active or not data.selected: return refused[FullPagedRoot](
      FullPagedNativeError.Uninitialized)
  if data.poisoned: return refused[FullPagedRoot](FullPagedNativeError.RecoveryRequired)
  let held = data.head.check
  if held != FileError.None: return fileFailed[FullPagedRoot](held)
  let header = data.checked.header
  for index in 0..<header.len:
    # Exact full-root metadata grants counts only; complete-map reconstruction independently recomputes the JAM root.
    let claim = header.retainedRoot(index)
    if array[32, byte](claim.root) == array[32, byte](root):
      return FullPagedNativeResult[FullPagedRoot](status: FullPagedNativeError.None,
          completed: claim)
  FullPagedNativeResult[FullPagedRoot](status: FullPagedNativeError.GraphFailure,
    graphCause: FullPagedStreamError.UnknownRoot, graphCodec: FullPagedError.Uninitialized)
proc visitEntries*(writer: FullPagedWriter, root: StateRoot, visitor: nil FullPagedEntryVisitor,
    budget: FullPagedWorkLimits): FullPagedNativeResult[FullPagedCounts] =
  ## Synchronously borrow the immutable selected head; callers stage every value privately until traversal completes.
  let data = writer.data
  if data == nil or not data.active or not data.selected: return refused[FullPagedCounts](
      FullPagedNativeError.Uninitialized)
  if data.poisoned: return refused[FullPagedCounts](FullPagedNativeError.RecoveryRequired)
  let streamed = data.head.streamFullEntries(data.checked, root, visitor, budget)
  if streamed.error != FullPagedStreamError.None: return graphFailed[FullPagedCounts,
      FullPagedCounts](streamed)
  FullPagedNativeResult[FullPagedCounts](status: FullPagedNativeError.None,
      completed: streamed.value)
proc visitEntries*(writer: FullPagedWriter, root: StateRoot,
    visitor: nil FullPagedEntryVisitor): FullPagedNativeResult[FullPagedCounts] =
  ## Omitted traversal budgets preserve every originally admitted finite work ceiling.
  let data = writer.data
  if data == nil or not data.active or not data.selected: return refused[FullPagedCounts](
      FullPagedNativeError.Uninitialized)
  writer.visitEntries(root, visitor, data.checked.limits.work)

proc synchronize*(writer: var FullPagedWriter): FullPagedNativeResult[StorageDurability] =
  ## Confirm fresh selected-file and directory barriers under the held exact CURRENT and writer lease.
  let data = writer.data
  if data == nil or not data.active: return refused[StorageDurability](
      FullPagedNativeError.Uninitialized)
  let selected = current(data)
  if selected != FileError.None: return fileFailed[StorageDurability](selected)
  let file = data.head.synchronize
  if file != FileError.None:
    data.poisoned = true # Failed durability cannot revive the remembered selected owner.
    return fileFailed[StorageDurability](file)
  let directory = data.directory.synchronize
  if directory != FileError.None:
    data.poisoned = true # A successful file barrier alone never grants the complete receipt.
    return fileFailed[StorageDurability](directory)
  FullPagedNativeResult[StorageDurability](status: FullPagedNativeError.None,
    completed: StorageDurability.FileAndDirectorySynced)
