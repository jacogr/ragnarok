# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Erasure-code final ordered exports and proof pages from one original executed-bundle provenance.

import ../../codec/bounded
import ../../codec/work/[digest as work_digest, report as work_report]
import ../../pvm/host/fetch as host_fetch
import ../bundle_erasure
import ../erasure/[layout as erasure_layout, words as erasure_words]
import ../[auditable_bundle, input_refinement]
import ./commitment as export_commitment
import ../report/identity as report_identity
import ../authorized_refinement
import ../refinement/[digest as refinement_digest, report as refinement_report]

type
  ExportErasureError* {.pure.} = enum ## Refusals expose no partial export/page encoding or substitute tree.
    Uninitialized, None, InvalidSource, LimitExceeded, CommitmentFailure, EncodingFailure, InvalidIndex
  ExportErasureIndex* = distinct uint64 ## Combined row ordinal: all final exports followed by all proof pages.
  ExportErasureLimits* = object ## Aggregate coding policies and separate export-tree/hash policies.
    bytes*: ByteLimit
    products*: FieldProductLimit
    commitment*: ExportCommitmentLimits
  ExportErasureInfo* = object ## Copied original identity/root, combined row dimensions and complete coding work facts.
    packageHash*: PackageHash
    root*: SegmentRoot
    exports*: SegmentCount
    pages*, rows*, retainedBytes*, workspaceBytes*, products*: uint64
    geometry*: ErasureGeometry
  ExportErasureData = ref object ## Immutable acyclic ownership retains both original bundle and derived export commitment.
    source: BundleErasure
    commitment: ExportCommitment
    info: ExportErasureInfo
    encoded: seq[byte]
  ExportErasure* = object ## Defaults have no successful empty encoding or computed export root.
    data: nil ExportErasureData
  ExportErasureResult*[T] = object ## Private success alternatives preserve checked selection under optimization.
    case status: ExportErasureError
    of None:
      completed: T
    else:
      discard # Refusals retain only their reason, never successful prefixes.

func error*[T](outcome: ExportErasureResult[T]): ExportErasureError =
  ## Inspect the selected reason without exposing mutable result tags.
  outcome.status

func value*[T](outcome: ExportErasureResult[T]): T
    {.requires: outcome.status == ExportErasureError.None.} =
  ## Extract only a complete checked success.
  outcome.completed

proc exportErasureInfo*(owner: ExportErasure): ExportErasureResult[ExportErasureInfo] =
  ## Copy aggregate fixed facts without exposing retained encoded storage.
  let data = owner.data
  if data == nil: return ExportErasureResult[ExportErasureInfo](
      status: ExportErasureError.Uninitialized)
  ExportErasureResult[ExportErasureInfo](status: ExportErasureError.None, completed: data.info)

proc exportErasureSource*(owner: ExportErasure): ExportErasureResult[BundleErasure] =
  ## Retain the exact original completed bundle encoding rather than accepting a replacement source.
  let data = owner.data
  if data == nil: return ExportErasureResult[BundleErasure](
      status: ExportErasureError.Uninitialized)
  ExportErasureResult[BundleErasure](status: ExportErasureError.None, completed: data.source)

proc exportErasureCommitment*(owner: ExportErasure): ExportErasureResult[ExportCommitment] =
  ## Retain the tree computed from this same original executed identity.
  let data = owner.data
  if data == nil: return ExportErasureResult[ExportCommitment](
      status: ExportErasureError.Uninitialized)
  ExportErasureResult[ExportCommitment](status: ExportErasureError.None, completed: data.commitment)

proc exportErasureChunk*(owner: ExportErasure, shard: ErasureShardIndex,
    row: ExportErasureIndex): ExportErasureResult[seq[byte]] =
  ## Copy a complete data/page chunk after checking both full-width coordinates before arithmetic.
  let data = owner.data
  if data == nil: return ExportErasureResult[seq[byte]](status: ExportErasureError.Uninitialized)
  if uint64(shard) >= uint64(uint16(data.info.geometry.shards)) or uint64(row) >= data.info.rows:
    return ExportErasureResult[seq[byte]](status: ExportErasureError.InvalidIndex)
  let count = int(data.info.geometry.segmentChunkBytes)
  let first = int((uint64(shard)*data.info.rows+uint64(row))*data.info.geometry.segmentChunkBytes)
  # Entire output fits int and validated coordinates bound the slice before conversion/multiplication.
  var copied = newSeq[byte](count)
  for position in 0..<count: copied[position] = data.encoded[first+position]
  ExportErasureResult[seq[byte]](status: ExportErasureError.None, completed: copied)

proc encodeSegment(segment: FetchSegment, row, rows: int, geometry: ErasureGeometry,
    input: var seq[ErasureWord], encoded: var seq[byte], limits: ErasureWordLimits): bool =
  ## Transpose one original fixed segment through scalar encoding into the preflighted validator-major buffer.
  let bytes = array[4104, byte](segment)
  let width = int(geometry.segmentChunkBytes)
  for column in 0..<width div 2:
    for index in 0..<input.len:
      let offset = index*width+column*2 # Original count times width equals 4104 exactly.
      input[index] = ErasureWord(uint16(bytes[offset]) or (uint16(bytes[offset+1]) shl 8))
    let coded = encodeErasureWords(input, geometry.shards, limits)
    if coded.error != ErasureWordError.None: return false
    for shard in 0..<int(uint16(geometry.shards)):
      let word = uint16(coded.value.codeWord(ErasureShardIndex(uint64(shard))).value)
      let offset = (shard*rows+row)*width+column*2
      encoded[offset] = byte(word and 255)
      encoded[offset+1] = byte(word shr 8)
  true

proc prepareExportErasure*(source: BundleErasure, limits: ExportErasureLimits): ExportErasureResult[
    ExportErasure] =
  ## Derive the original execution/tree and preflight complete coding before any hash or payload extraction.
  template fail(reason: ExportErasureError) =
    return ExportErasureResult[ExportErasure](status: reason)
  let described = source.bundleErasureInfo
  if described.error != BundleErasureError.None: fail(ExportErasureError.InvalidSource)
  let geometry = described.value.geometry
  let identity = source.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  let report = identity.identitySource.value.authorizedDigests.value.digestReport.value
  let count = uint64(report.reportInfo.value.exports)
  if count > 3072: fail(ExportErasureError.LimitExceeded)
  let pages = (count+63) div 64
  let rows = count+pages
  let original = int(geometry.originalShards)
  let validators = int(uint16(geometry.shards))
  var span = 1
  while span < original: span *= 2 # Originals <=342 prove span <=512 before doubling.
  let perColumn = uint64(31*(span-1)+original*(original-1) div 2+(validators-original)*(original-1))
  let scalarBytes = uint64(validators+original+span)*2
  let products = rows*(geometry.segmentChunkBytes div 2)*perColumn
  let retained = uint64(validators)*rows*geometry.segmentChunkBytes
  let workspace = if rows == 0: 0'u64 else: uint64(original)*2+scalarBytes
  if retained > uint64(high(int)) or retained+workspace > uint64(limits.bytes): fail(
      ExportErasureError.LimitExceeded)
  if products > uint64(limits.products): fail(ExportErasureError.LimitExceeded)
  let prepared = prepareExportCommitment(identity, limits.commitment)
  if prepared.error == ExportCommitmentError.LimitExceeded: fail(ExportErasureError.LimitExceeded)
  if prepared.error != ExportCommitmentError.None: fail(ExportErasureError.CommitmentFailure)
  let commitment = prepared.value
  let tree = commitment.commitmentInfo.value
  var encoded = newSeq[byte](int(retained))
  # Empty exports require no scalar input, inverse table or coefficient allocation.
  if rows > 0:
    var input = newSeq[ErasureWord](original)
    let scalarLimits = ErasureWordLimits(bytes: ByteLimit(scalarBytes), products: FieldProductLimit(perColumn))
    var row = 0
    # Final normalized item/segment ordering includes synthesized zero exports for every failed item.
    for itemIndex in 0..<report.reportInfo.value.items:
      let item = report.reportItem(FetchItemIndex(uint64(itemIndex))).value
      for segmentIndex in 0..<int(uint64(item.refinedInfo.value.exports)):
        let segment = item.refinedSegment(ExportCount(uint64(segmentIndex))).value
        if not encodeSegment(segment, row, int(rows), geometry, input, encoded, scalarLimits):
          fail(ExportErasureError.EncodingFailure)
        inc row
    # Proof pages follow every original data segment; each page is encoded independently with no extra framing.
    for page in 0..<int(pages):
      let segment = commitment.commitmentPage(ExportPageIndex(uint64(page))).value
      if not encodeSegment(segment, row, int(rows), geometry, input, encoded, scalarLimits):
        fail(ExportErasureError.EncodingFailure)
      inc row
    if uint64(row) != rows: fail(ExportErasureError.EncodingFailure) # Never publish an incomplete private buffer.
  ExportErasureResult[ExportErasure](status: ExportErasureError.None,
    completed: ExportErasure(data: ExportErasureData(source: source, commitment: commitment,
      encoded: encoded,
      info: ExportErasureInfo(packageHash: described.value.packageHash, root: tree.root,
        exports: tree.exports,
        pages: pages, rows: rows, geometry: geometry, retainedBytes: retained,
        workspaceBytes: workspace, products: products))))
