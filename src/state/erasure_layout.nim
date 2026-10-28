# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Pinned erasure geometry and source-bound systematic bundle chunks, before parity encoding.

import ../codec/bounded as codec_bounded
import ../codec/work_report as codec_work_report
import ./auditable_bundle as state_auditable_bundle

type
  ErasureLayoutError* {.pure.} = enum ## Refusals contain no partial padded buffer or fabricated chunk.
    Uninitialized, None, InvalidSource, InvalidShards, LimitExceeded, InvalidIndex
  OriginalShardIndex* = distinct uint64 ## Only original systematic shard ordinals are accepted here.
  ErasureGeometry* = object ## Copied descriptive sizes do not certify parity or an availability root.
    shards*: ErasureShards
    originalShards*, stripeBytes*, bundleChunkBytes*, segmentChunkBytes*: uint64
    paddedBytes*, paddingBytes*, encodedBytes*: uint64
  LayoutData = ref object ## Immutable acyclic ownership retains original executed bundle provenance.
    source: AuditableBundle
    geometry: ErasureGeometry
    padded: seq[byte]
  ErasureLayout* = object ## Only successful preparation initializes the source and padded storage.
    data: nil LayoutData
  ErasureLayoutResult*[T] = object ## Private result selection remains guarded in optimized builds.
    case status: ErasureLayoutError
    of None:
      completed: T
    else:
      discard                      # No successful prefix is available on refusal.

func error*[T](outcome: ErasureLayoutResult[T]): ErasureLayoutError =
  ## Inspect the selected reason without exposing writable variant tags.
  outcome.status
func value*[T](outcome: ErasureLayoutResult[T]): T
    {.requires: outcome.status == ErasureLayoutError.None.} =
  ## Extract only a complete successful value.
  outcome.completed
proc erasureGeometry*(length: BundleLength, shards: ErasureShards): ErasureLayoutResult[
    ErasureGeometry] =
  ## Apply pinned valcount and greatest-divisor geometry without allocating or narrowing lengths.
  let count = uint64(uint16(shards))
  if count < 6 or count > 1023 or count mod 3 != 0:
    return ErasureLayoutResult[ErasureGeometry](status: ErasureLayoutError.InvalidShards)
  var original = count div 3+1
  # One always divides 2052; the search cannot underflow and starts at most 342.
  while 2052 mod original != 0: dec original
  let stripe = original*2
  let bytes = uint64(uint32(length))
  let words = (bytes+stripe-1) div stripe # E4 plus at most 683 fits uint64.
  let padded = words*stripe # At most E4 plus one stripe; no native allocation occurs here.
  let chunk = words*2
  ErasureLayoutResult[ErasureGeometry](status: ErasureLayoutError.None,
    completed: ErasureGeometry(shards: shards, originalShards: original, stripeBytes: stripe,
      bundleChunkBytes: chunk, segmentChunkBytes: 4104 div original,
      paddedBytes: padded, paddingBytes: padded-bytes, encodedBytes: chunk*count))
proc layoutInfo*(layout: ErasureLayout): ErasureLayoutResult[ErasureGeometry] =
  ## Copy fixed geometry only from completed source-bound preparation.
  let data = layout.data
  if data == nil: return ErasureLayoutResult[ErasureGeometry](
      status: ErasureLayoutError.Uninitialized)
  ErasureLayoutResult[ErasureGeometry](status: ErasureLayoutError.None, completed: data.geometry)
proc layoutSource*(layout: ErasureLayout): ErasureLayoutResult[AuditableBundle] =
  ## Retain the exact original bundle rather than accepting later detached byte/identity tuples.
  let data = layout.data
  if data == nil: return ErasureLayoutResult[AuditableBundle](
      status: ErasureLayoutError.Uninitialized)
  ErasureLayoutResult[AuditableBundle](status: ErasureLayoutError.None, completed: data.source)
proc originalChunk*(layout: ErasureLayout, index: OriginalShardIndex): ErasureLayoutResult[seq[byte]] =
  ## Copy one contiguous systematic chunk; parity positions have no successful value in this layer.
  let data = layout.data
  if data == nil: return ErasureLayoutResult[seq[byte]](status: ErasureLayoutError.Uninitialized)
  if uint64(index) >= data.geometry.originalShards:
    return ErasureLayoutResult[seq[byte]](status: ErasureLayoutError.InvalidIndex)
  let count = int(data.geometry.bundleChunkBytes)
  let first = int(uint64(index)*data.geometry.bundleChunkBytes)
  # Preparation proves the entire padded buffer fits int; index bounds prove this slice is inside it.
  var copied = newSeq[byte](count)
  for position in 0..<count: copied[position] = data.padded[first+position]
  ErasureLayoutResult[seq[byte]](status: ErasureLayoutError.None, completed: copied)
proc prepareErasureLayout*(source: AuditableBundle, shards: ErasureShards,
    limit: ByteLimit): ErasureLayoutResult[ErasureLayout] =
  ## Preflight the entire padded buffer before copying bytes from the exact original executed bundle.
  let described = source.bundleInfo
  if described.error != AuditableBundleError.None:
    return ErasureLayoutResult[ErasureLayout](status: ErasureLayoutError.InvalidSource)
  let computed = erasureGeometry(described.value.length, shards)
  if computed.error != ErasureLayoutError.None:
    return ErasureLayoutResult[ErasureLayout](status: computed.error)
  let geometry = computed.value
  if geometry.paddedBytes > uint64(high(int)) or geometry.paddedBytes > uint64(limit):
    return ErasureLayoutResult[ErasureLayout](status: ErasureLayoutError.LimitExceeded)
  var padded = source.bundleBytes.value # Independent copy; no mutable descriptor aliases the retained source.
  padded.setLen(int(geometry.paddedBytes))
  # Explicitly initialize appended bytes rather than depending on allocator or compiler zeroing.
  for position in int(uint32(described.value.length))..<padded.len: padded[position] = 0
  ErasureLayoutResult[ErasureLayout](status: ErasureLayoutError.None,
    completed: ErasureLayout(data: LayoutData(source: source, geometry: geometry, padded: padded)))
