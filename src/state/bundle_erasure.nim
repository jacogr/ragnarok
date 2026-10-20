# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Encode all GP audit-bundle shards from one immutable executed-bundle layout.

import ../codec/[bounded, work_report]
import ./[auditable_bundle, erasure_layout, erasure_words]

type
  BundleErasureError* {.pure.} = enum ## Refusals contain no encoded prefix or replacement provenance.
    Uninitialized, None, InvalidSource, LimitExceeded, EncodingFailure, InvalidIndex
  BundleErasureLimits* = object ## Aggregate logical buffer payload and full scalar field-work policies.
    bytes*: ByteLimit
    products*: FieldProductLimit
  BundleErasureInfo* = object ## Copied original identity, validated geometry and complete encoding work facts.
    packageHash*: PackageHash
    length*: BundleLength
    geometry*: ErasureGeometry
    retainedBytes*, workspaceBytes*, products*: uint64
  BundleErasureData = ref object ## Immutable acyclic storage retains the exact original layout and complete chunk bytes.
    source: ErasureLayout
    info: BundleErasureInfo
    encoded: seq[byte]
  BundleErasure* = object ## Defaults carry no completed bundle encoding.
    data: nil BundleErasureData
  BundleErasureResult*[T] = object ## Private success payloads require checked selection even under optimization.
    case status: BundleErasureError
    of None:
      completed: T
    else:
      discard # Refusals retain no partial output, scalar code or caller-visible buffer.

func error*[T](outcome: BundleErasureResult[T]): BundleErasureError =
  ## Inspect the selected reason without exposing a writable variant tag.
  outcome.status
func value*[T](outcome: BundleErasureResult[T]): T
    {.requires: outcome.status == BundleErasureError.None.} =
  ## Extract only a complete selected success.
  outcome.completed
proc bundleErasureInfo*(bundle: BundleErasure): BundleErasureResult[BundleErasureInfo] =
  ## Copy fixed facts without exposing retained encoded storage.
  let data = bundle.data
  if data == nil: return BundleErasureResult[BundleErasureInfo](
      status: BundleErasureError.Uninitialized)
  BundleErasureResult[BundleErasureInfo](status: BundleErasureError.None, completed: data.info)
proc bundleErasureSource*(bundle: BundleErasure): BundleErasureResult[ErasureLayout] =
  ## Retain the exact original completed layout rather than accepting substitute geometry or bytes.
  let data = bundle.data
  if data == nil: return BundleErasureResult[ErasureLayout](
      status: BundleErasureError.Uninitialized)
  BundleErasureResult[ErasureLayout](status: BundleErasureError.None, completed: data.source)
proc bundleErasureChunk*(bundle: BundleErasure, index: ErasureShardIndex): BundleErasureResult[seq[byte]] =
  ## Copy one complete systematic or parity chunk using its full-width validator ordinal.
  let data = bundle.data
  if data == nil: return BundleErasureResult[seq[byte]](status: BundleErasureError.Uninitialized)
  if uint64(index) >= uint64(uint16(data.info.geometry.shards)):
    return BundleErasureResult[seq[byte]](status: BundleErasureError.InvalidIndex)
  let count = int(data.info.geometry.bundleChunkBytes)
  let first = int(uint64(index)*data.info.geometry.bundleChunkBytes)
  # Preparation bounds the entire encoded buffer before conversion; the index proof bounds this slice.
  var copied = newSeq[byte](count)
  for position in 0..<count: copied[position] = data.encoded[first+position]
  BundleErasureResult[seq[byte]](status: BundleErasureError.None, completed: copied)
proc prepareBundleErasure*(source: ErasureLayout, limits: BundleErasureLimits): BundleErasureResult[
    BundleErasure] =
  ## Preflight aggregate output/workspace and every word-column product before payload extraction or allocation.
  template fail(reason: BundleErasureError) =
    return BundleErasureResult[BundleErasure](status: reason)
  let described = source.layoutInfo
  if described.error != ErasureLayoutError.None: fail(BundleErasureError.InvalidSource)
  let geometry = described.value
  let originalBundle = source.layoutSource.value
  let originalInfo = originalBundle.bundleInfo.value
  let count = int(uint16(geometry.shards))
  let original = int(geometry.originalShards)
  var span = 1
  while span < original: span *= 2 # Validated originals <=342 prove span <=512 before doubling.
  let columnProducts = uint64(31*(span-1)+original*(original-1) div 2+(count-original)*(original-1))
  let scalarBytes = uint64(count+original+span)*2
  let products = geometry.bundleChunkBytes div 2*columnProducts
  let workspace = uint64(uint32(originalInfo.length))+uint64(original)*2+scalarBytes
  if geometry.encodedBytes > uint64(high(int)): fail(BundleErasureError.LimitExceeded)
  if geometry.encodedBytes+workspace > uint64(limits.bytes) or products > uint64(limits.products):
    fail(BundleErasureError.LimitExceeded)
  let bytes = originalBundle.bundleBytes.value # Copy only after all complete-operation budgets pass.
  var input = newSeq[ErasureWord](original)
  var encoded = newSeq[byte](int(geometry.encodedBytes))
  let chunkBytes = int(geometry.bundleChunkBytes)
  let columnLimits = ErasureWordLimits(bytes: ByteLimit(scalarBytes), products: FieldProductLimit(columnProducts))
  # Original chunks are contiguous; zero suffixes are synthesized before little-endian word decoding.
  for column in 0..<chunkBytes div 2:
    for index in 0..<original:
      let offset = index*chunkBytes+column*2
      var word = 0'u16
      if offset < bytes.len: word = uint16(bytes[offset])
      if offset+1 < bytes.len: word = word or (uint16(bytes[offset+1]) shl 8)
      input[index] = ErasureWord(word)
    let coded = encodeErasureWords(input, geometry.shards, columnLimits)
    if coded.error != ErasureWordError.None: fail(BundleErasureError.EncodingFailure)
    # Write each output pair to its validator's chunk, never to a column-major wire sequence.
    for index in 0..<count:
      let word = uint16(coded.value.codeWord(ErasureShardIndex(uint64(index))).value)
      let offset = index*chunkBytes+column*2
      encoded[offset] = byte(word and 255)
      encoded[offset+1] = byte(word shr 8)
  BundleErasureResult[BundleErasure](status: BundleErasureError.None,
    completed: BundleErasure(data: BundleErasureData(source: source, encoded: encoded,
      info: BundleErasureInfo(packageHash: originalInfo.packageHash, length: originalInfo.length,
        geometry: geometry, retainedBytes: geometry.encodedBytes, workspaceBytes: workspace,
        products: products))))
