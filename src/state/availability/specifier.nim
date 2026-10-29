# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Assemble GP availability commitments from one original bundle/export erasure owner.

import ../../codec/bounded
import ../../codec/work/report as work_report
import ../../crypto/primitives
import ../bundle_erasure
import "../export/erasure" as export_erasure
import ../erasure/words as erasure_words

type
  AvailabilityCommitmentError* {.pure.} = enum ## Refusals expose no partial root or computed validator prefix.
    Uninitialized, None, InvalidSource, LimitExceeded, BackendFailure, InvalidIndex
  AvailabilitySpecifier* = object ## Six copied nominal GP availability fields; only completed owners bind their provenance.
    packageHash*: PackageHash
    bundleLength*: BundleLength
    erasureRoot*: ErasureRoot
    erasureShards*: ErasureShards
    segmentRoot*: SegmentRoot
    segmentCount*: SegmentCount
  AvailabilityCommitmentLimits* = object ## Logical buffers, complete hash-call count and exact preimage work policies.
    bytes*, hashBytes*: ByteLimit
    hashes*: ElementLimit
  AvailabilityCommitmentInfo* = object ## Copied metadata and complete resource facts cannot mutate retained commitment authority.
    specifier*: AvailabilitySpecifier
    retainedBytes*, workspaceBytes*, hashes*, hashBytes*: uint64
  AvailabilityShardInfo* = object ## Copied per-validator bundle hash and well-balanced export/page root.
    bundleHash*, exportRoot*: Blake2bHash
  AvailabilityData = ref object ## Immutable acyclic ownership retains original erasure provenance and fixed validator leaves.
    source: ExportErasure
    info: AvailabilityCommitmentInfo
    leaves: seq[byte]
  AvailabilityCommitment* = object ## Defaults carry no computed availability specifier.
    data: nil AvailabilityData
  AvailabilityCommitmentResult*[T] = object ## Private alternatives require checked success selection in optimized builds.
    case status: AvailabilityCommitmentError
    of None:
      completed: T
    else:
      discard # No partial validator prefix or default root accompanies a refusal.

func error*[T](outcome: AvailabilityCommitmentResult[T]): AvailabilityCommitmentError =
  ## Read the selected reason without exposing writable variant fields.
  outcome.status
func value*[T](outcome: AvailabilityCommitmentResult[T]): T
    {.requires: outcome.status == AvailabilityCommitmentError.None.} =
  ## Extract only a complete selected success.
  outcome.completed
proc availabilityInfo*(owner: AvailabilityCommitment): AvailabilityCommitmentResult[
    AvailabilityCommitmentInfo] =
  ## Copy fixed specifier/resource facts from a completed immutable owner.
  let data = owner.data
  if data == nil: return AvailabilityCommitmentResult[AvailabilityCommitmentInfo](
      status: AvailabilityCommitmentError.Uninitialized)
  AvailabilityCommitmentResult[AvailabilityCommitmentInfo](status: AvailabilityCommitmentError.None,
      completed: data.info)
proc availabilitySource*(owner: AvailabilityCommitment): AvailabilityCommitmentResult[
    ExportErasure] =
  ## Retain the exact original executed bundle/export encoding rather than allowing detached replacements.
  let data = owner.data
  if data == nil: return AvailabilityCommitmentResult[ExportErasure](
      status: AvailabilityCommitmentError.Uninitialized)
  AvailabilityCommitmentResult[ExportErasure](status: AvailabilityCommitmentError.None,
      completed: data.source)
proc availabilityShard*(owner: AvailabilityCommitment,
    index: ErasureShardIndex): AvailabilityCommitmentResult[AvailabilityShardInfo] =
  ## Copy both validator hashes after checking the full-width index before arithmetic or narrowing.
  let data = owner.data
  if data == nil: return AvailabilityCommitmentResult[AvailabilityShardInfo](
      status: AvailabilityCommitmentError.Uninitialized)
  if uint64(index) >= uint64(uint16(data.info.specifier.erasureShards)):
    return AvailabilityCommitmentResult[AvailabilityShardInfo](
        status: AvailabilityCommitmentError.InvalidIndex)
  let first = int(uint64(index))*64 # Validated validator counts bound this to the retained leaf buffer.
  var bundle = default(array[32, byte])
  var exports = default(array[32, byte])
  for position in 0..<32:
    bundle[position] = data.leaves[first+position]
    exports[position] = data.leaves[first+32+position]
  AvailabilityCommitmentResult[AvailabilityShardInfo](status: AvailabilityCommitmentError.None,
    completed: AvailabilityShardInfo(bundleHash: Blake2bHash(bundle), exportRoot: Blake2bHash(exports)))
func treeCalls(count: uint64): uint64 =
  ## Count GP well-balanced hash calls without treating internal singleton leaves as hashes.
  if count == 0: 0'u64
  elif count == 1: 1'u64
  else: count-1
func treeBytes(count, width: uint64): uint64 =
  ## Sum raw leaf bytes, four-byte node prefixes and hashed-child edges exactly once.
  if count == 0: 0'u64
  elif count == 1: width
  else: count*width+4*(count-1)+32*(count-2)
proc nodeHash(bytes: openArray[byte], width, first, count: int): AvailabilityCommitmentResult[Blake2bHash] =
  ## Hash a non-singleton GP N subtree; singleton children contribute raw leaves without separate hashing.
  let left = (count+1) div 2
  let right = count-left
  var preimage = default(array[2740, byte])
  preimage[0] = byte('n')
  preimage[1] = byte('o')
  preimage[2] = byte('d')
  preimage[3] = byte('e')
  var cursor = 4
  # Subtree sizes are ceil/floor halves; recursion depth is bounded by the immutable source's 3120-row ceiling.
  for side in 0..<2:
    let start = if side == 0: first else: first+left
    let size = if side == 0: left else: right
    if size == 1:
      for position in 0..<width:
        preimage[cursor] = bytes[start*width+position] # Raw leaf extent is at most 1368 bytes.
        inc cursor
    else:
      let child = nodeHash(bytes, width, start, size)
      if child.error != AvailabilityCommitmentError.None: return child
      for octet in array[32, byte](child.value):
        preimage[cursor] = octet
        inc cursor
  let hashed = blake2b256(preimage.toOpenArray(0, cursor-1))
  if hashed.error != CryptoError.None:
    return AvailabilityCommitmentResult[Blake2bHash](
        status: AvailabilityCommitmentError.BackendFailure)
  AvailabilityCommitmentResult[Blake2bHash](status: AvailabilityCommitmentError.None,
      completed: hashed.value)
proc balancedRoot(bytes: openArray[byte], width, count: int): AvailabilityCommitmentResult[Blake2bHash] =
  ## Apply WB's empty/singleton special cases before the unpadded raw-leaf N transform.
  if count == 0:
    return AvailabilityCommitmentResult[Blake2bHash](status: AvailabilityCommitmentError.None,
        completed: Blake2bHash(default(array[32, byte])))
  if count == 1:
    let hashed = blake2b256(bytes)
    if hashed.error != CryptoError.None:
      return AvailabilityCommitmentResult[Blake2bHash](
          status: AvailabilityCommitmentError.BackendFailure)
    return AvailabilityCommitmentResult[Blake2bHash](status: AvailabilityCommitmentError.None,
        completed: hashed.value)
  nodeHash(bytes, width, 0, count)
proc prepareAvailabilityCommitment*(source: ExportErasure,
    limits: AvailabilityCommitmentLimits): AvailabilityCommitmentResult[AvailabilityCommitment] =
  ## Preflight complete memory/hash work before extracting any chunk or computing a validator prefix.
  template fail(reason: AvailabilityCommitmentError) =
    return AvailabilityCommitmentResult[AvailabilityCommitment](status: reason)
  let described = source.exportErasureInfo
  if described.error != ExportErasureError.None: fail(AvailabilityCommitmentError.InvalidSource)
  let info = described.value
  let bundle = source.exportErasureSource.value
  let original = bundle.bundleErasureInfo.value
  let validators = uint64(uint16(info.geometry.shards))
  let width = info.geometry.segmentChunkBytes
  let retained = validators*64
  let workspace = info.rows*width+info.geometry.bundleChunkBytes+(if info.rows ==
      0: 0'u64 else: width)
  let calls = validators*(1+treeCalls(info.rows))+treeCalls(validators)
  let hashBytes = validators*(info.geometry.bundleChunkBytes+treeBytes(info.rows, width))+treeBytes(
      validators, 64)
  if retained+workspace > uint64(limits.bytes) or calls > uint64(limits.hashes): fail(
      AvailabilityCommitmentError.LimitExceeded)
  if hashBytes > uint64(limits.hashBytes): fail(AvailabilityCommitmentError.LimitExceeded)
  var leaves = newSeq[byte](int(retained))
  var exportChunks = newSeq[byte](int(info.rows*width))
  # The source already proves every count/width product fits native indexing; its complete buffers are retained separately.
  for validator in 0..<int(validators):
    let shard = ErasureShardIndex(uint64(validator))
    let chunk = bundle.bundleErasureChunk(shard).value
    let hashed = blake2b256(chunk)
    if hashed.error != CryptoError.None: fail(AvailabilityCommitmentError.BackendFailure)
    for row in 0..<int(info.rows):
      let exported = source.exportErasureChunk(shard, ExportErasureIndex(uint64(row))).value
      for position in 0..<int(width): exportChunks[row*int(width)+position] = exported[position]
    let root = balancedRoot(exportChunks, int(width), int(info.rows))
    if root.error != AvailabilityCommitmentError.None: fail(root.error)
    for position in 0..<32:
      leaves[validator*64+position] = array[32, byte](hashed.value)[position]
      leaves[validator*64+32+position] = array[32, byte](root.value)[position]
  let root = balancedRoot(leaves, 64, int(validators))
  if root.error != AvailabilityCommitmentError.None: fail(root.error)
  AvailabilityCommitmentResult[AvailabilityCommitment](status: AvailabilityCommitmentError.None,
    completed: AvailabilityCommitment(data: AvailabilityData(source: source, leaves: leaves,
      info: AvailabilityCommitmentInfo(retainedBytes: retained, workspaceBytes: workspace,
        hashes: calls, hashBytes: hashBytes,
        specifier: AvailabilitySpecifier(packageHash: info.packageHash,
          bundleLength: original.length,
          erasureRoot: ErasureRoot(bytes: array[32, byte](root.value)),
              erasureShards: info.geometry.shards,
          segmentRoot: info.root, segmentCount: info.exports)))))
