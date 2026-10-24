# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full-state paged native readers retain independent immutable epoch pins after complete graph admission.
## Explicit close exposes retirement uncertainty; no reader owns a writer lease, callback or resident graph.
## One caller serializes operations per owner; independent readers have independent native seek cursors.
import std/assertions
import ./[full_paged_codec, full_paged_stream, paged_io, paged_codec, database_identity, file_errors]
import ../codec/[state_layout, state_trie]

type
  FullPagedNativeError* {.pure.} = enum ## Failed/default native results contain no retained reader or graph receipt.
    Uninitialized, None, FileFailure, CodecFailure, GraphFailure
  FullPagedNativeResult*[T] = object ## Private selected alternatives retain only their precise diagnostic.
    case status: FullPagedNativeError
    of None: completed: T
    of FileFailure: fileCause: FileError
    of CodecFailure: codecCause: FullPagedError
    of GraphFailure:
      graphCause: FullPagedStreamError
      graphCodec: FullPagedError
    else: discard
  FullPagedNativeConfig* = object ## Expected chain/root and finite policy are selected independently of disk.
    chain*: StorageChainId
    root*: StateRoot
    limits*: FullPagedStreamLimits
  ReaderData = ref object ## One immutable native pin; only explicit retirement can release its descriptor.
    file: PagedFile
    checked: CheckedFullPagedArtifact
    active: bool
  FullPagedReader* = object ## Unique explicit-close reader authority survives directory/writer retirement.
    data: nil ReaderData
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
