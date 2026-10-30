# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bind verified leaves to the exact original package derived from verified extrinsic ownership.
## Explicit lookup values resolve package references but do not certify root freshness/correspondence.

import ../../codec/bounded
import ../../codec/work/[package as work_package, report as work_report]
import ../../pvm/host/fetch as host_fetch
import ../extrinsic_inputs
import ./justification as import_justification

type
  ImportInputsError* {.pure.} = enum ## Refusals contain no partial manifest/input binding.
    Uninitialized, None, InvalidSource, InvalidShape, InvalidLookup, NonCanonical,
    InvalidImport, IndexMismatch, RootMismatch, LimitExceeded, InvalidIndex
  ImportInputIndex* = distinct uint64 ## Import occurrence ordinal within an item differs from the exported leaf's ImportIndex.
  ImportInputsLimits* = object ## Local caps count repeated occurrences and their logical leaf/proof payload independently.
    entries*: ElementLimit
    witnessBytes*: ByteLimit
  ImportInputsInfo* = object ## Fixed copied facts carry accounting, never replaceable package or proof authority.
    items*, entries*, lookupCount*: int
    witnessBytes*: uint64
  InputsData = ref object ## Acyclic immutable storage retains original extrinsics and verified import owners.
    extrinsics: VerifiedExtrinsics
    info: ImportInputsInfo
    lookup: array[8, SegmentLookup]
    rows: seq[seq[VerifiedImport]]
  VerifiedImportInputs* = object ## A default handle has no certificate even for an empty import manifest.
    data: nil InputsData
  ImportInputsResult*[T] = object ## Private alternatives guard all successful extraction in optimized builds.
    case status: ImportInputsError
    of None:
      completed: T
    else:
      discard # No authenticated prefix escapes a failed complete-table match.

func error*[T](outcome: ImportInputsResult[T]): ImportInputsError =
  ## Inspect a reason without a writable discriminator.
  outcome.status

func value*[T](outcome: ImportInputsResult[T]): T
    {.requires: outcome.status == ImportInputsError.None.} =
  ## Extract only a fully selected successful value.
  outcome.completed

proc importInputsInfo*(inputs: VerifiedImportInputs): ImportInputsResult[ImportInputsInfo] =
  ## Copy fixed accounting without exposing retained descriptors.
  let data = inputs.data
  if data == nil: return ImportInputsResult[ImportInputsInfo](
      status: ImportInputsError.Uninitialized)
  ImportInputsResult[ImportInputsInfo](status: ImportInputsError.None, completed: data.info)

proc importInputsExtrinsics*(inputs: VerifiedImportInputs): ImportInputsResult[VerifiedExtrinsics] =
  ## Retain the original verified extrinsics and their original package, never a caller replacement.
  let data = inputs.data
  if data == nil: return ImportInputsResult[VerifiedExtrinsics](
      status: ImportInputsError.Uninitialized)
  ImportInputsResult[VerifiedExtrinsics](status: ImportInputsError.None, completed: data.extrinsics)

proc importInputsLookup*(inputs: VerifiedImportInputs): ImportInputsResult[seq[SegmentLookup]] =
  ## Copy the complete exact dictionary; fixed hash records cannot alias retained storage.
  let data = inputs.data
  if data == nil: return ImportInputsResult[seq[SegmentLookup]](
      status: ImportInputsError.Uninitialized)
  var copied = newSeq[SegmentLookup](data.info.lookupCount)
  for index in 0..<copied.len: copied[index] = data.lookup[
      index] # Each returned sequence owns independent storage.
  ImportInputsResult[seq[SegmentLookup]](status: ImportInputsError.None, completed: copied)

proc importInput*(inputs: VerifiedImportInputs, item: FetchItemIndex,
    index: ImportInputIndex): ImportInputsResult[VerifiedImport] =
  ## Check complete nominal ordinals before narrowing and retain only the originally matched leaf owner.
  let data = inputs.data
  if data == nil: return ImportInputsResult[VerifiedImport](status: ImportInputsError.Uninitialized)
  if uint64(item) >= uint64(data.rows.len):
    return ImportInputsResult[VerifiedImport](status: ImportInputsError.InvalidIndex)
  if uint64(index) >= uint64(data.rows[int(uint64(item))].len):
    return ImportInputsResult[VerifiedImport](status: ImportInputsError.InvalidIndex)
  ImportInputsResult[VerifiedImport](status: ImportInputsError.None,
    completed: data.rows[int(uint64(item))][int(uint64(index))])

proc less(a, b: PackageHash): bool =
  ## Compare dictionary keys lexicographically by wire bytes without native endian conversions.
  for index in 0..<32:
    # The first differing byte decides order; equality must reject a duplicate key.
    if a.bytes[index] != b.bytes[index]: return a.bytes[index] < b.bytes[index]
  false

proc bindImportInputs*(extrinsics: VerifiedExtrinsics, rows: openArray[seq[VerifiedImport]],
    lookup: openArray[SegmentLookup], limits: ImportInputsLimits): ImportInputsResult[
        VerifiedImportInputs] =
  ## Borrow stable rows/dictionary synchronously; preflight the complete binding before retaining any variable rows.
  template fail(reason: ImportInputsError) =
    return ImportInputsResult[VerifiedImportInputs](status: reason)
  let source = extrinsics.extrinsicInputsPackage
  if source.error != ExtrinsicInputsError.None: fail(ImportInputsError.InvalidSource)
  let package = source.value
  let described = package.workPackageInfo.value
  if rows.len != described.items: fail(ImportInputsError.InvalidShape)
  if lookup.len > 8-described.context.prerequisiteCount: fail(ImportInputsError.InvalidLookup)
  # Canonical dictionaries are strictly sorted and unique, never silently reordered or deduplicated.
  for index in 1..<lookup.len:
    if not less(lookup[index-1].packageHash, lookup[index].packageHash):
      fail(ImportInputsError.NonCanonical)
  var seen = default(array[8, bool])
  var info = ImportInputsInfo(items: rows.len, lookupCount: lookup.len)
  # The owned package bounds loops to sixteen items and 3072 total import occurrences before any allocation.
  for item in 0..<rows.len:
    let selected = package.workItemAt(item).value
    if rows[item].len != selected.workItemInfo.value.imports: fail(ImportInputsError.InvalidShape)
    for index in 0..<rows[item].len:
      let reference = selected.importAt(index).value
      let verified = rows[item][index].verifiedImportInfo
      if verified.error != ImportJustificationError.None: fail(ImportInputsError.InvalidImport)
      if uint16(verified.value.index) != uint16(reference.index): fail(
          ImportInputsError.IndexMismatch)
      var root = SegmentRoot()
      case reference.kind
      of ImportKind.Root:
        root = reference.root # Direct roots use the literal nominal segment root, without lookup.
      of ImportKind.Package:
        var found = false
        # The preflighted eight-entry ceiling makes fixed seen storage and the bounded linear search safe.
        for key in 0..<lookup.len:
          if lookup[key].packageHash.bytes == reference.package.bytes:
            root = lookup[key].segmentRoot
            seen[key] = true
            found = true
        if not found: fail(ImportInputsError.InvalidLookup) # Missing keys cannot silently resolve to zero roots.
      if root.bytes != verified.value.root.bytes: fail(ImportInputsError.RootMismatch)
      inc info.entries
      info.witnessBytes += verified.value.payloadBytes # Each verified leaf is at most 4488 bytes; 3072 occurrences prove no wrap.
  # Exact key-set equality rejects unrelated keys even when all requested imports resolved.
  for index in 0..<lookup.len:
    if not seen[index]: fail(ImportInputsError.InvalidLookup)
  if uint64(info.entries) > uint64(limits.entries): fail(ImportInputsError.LimitExceeded)
  if info.witnessBytes > uint64(limits.witnessBytes): fail(ImportInputsError.LimitExceeded)
  var copied = newSeq[seq[VerifiedImport]](rows.len)
  # Capture independent row descriptors; immutable proof/segment owners can safely share acyclic ARC storage.
  for item in 0..<rows.len:
    copied[item] = newSeq[VerifiedImport](rows[item].len)
    for index in 0..<rows[item].len: copied[item][index] = rows[item][index]
  var dictionary = default(array[8, SegmentLookup])
  for index in 0..<lookup.len: dictionary[index] = lookup[
      index] # Retain fixed values, not the caller's descriptor.
  ImportInputsResult[VerifiedImportInputs](status: ImportInputsError.None,
    completed: VerifiedImportInputs(data: InputsData(extrinsics: extrinsics, info: info,
      rows: copied, lookup: dictionary)))
