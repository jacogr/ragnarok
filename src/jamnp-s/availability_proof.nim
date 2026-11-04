# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-bound CE137/138/140 transfer construction and exact root/coordinate-bound verification use bounded GP Merkle traces.
## Prepared/verified outputs contain independent immutable bytes only; canonical report authority remains with the caller.
import std/assertions
import ./availability_merkle
export AvailabilityMerkleLimits
import ../codec/bounded
from ../codec/work/report import ErasureRoot
import ../crypto/primitives
import ../state/availability/specifier
import ../state/erasure/[layout, words]
import ../state/bundle_erasure
import "../state/export/erasure" as export_erasure

const MaxAvailabilityBundleBytes* = 13904950'u64 ## GP full-bundle ceiling also bounds untrusted availability geometry before native allocation.
type
  AvailabilityTransferKind* {.pure.} = enum ## NP selectors distinguish all-data, bundle-only and one selected row evidence.
    Distribution, Audit, Segment
  AvailabilityRequest* = object ## Detached request facts confer neither native stream control nor expected-root authority.
    kind*: AvailabilityTransferKind
    root*: ErasureRoot
    shard*: ErasureShardIndex
    row*: ExportErasureIndex
  AvailabilityTransferError* {.pure.} = enum ## Refusals contain no verified or prepared byte prefix.
    Uninitialized, None, InvalidSpecifier, InvalidIndex, InvalidPayload, InvalidProof,
      LimitExceeded, RootMismatch, SourceFailure, GeometryFailure, MerkleFailure, BackendFailure
  AvailabilityTransferResult*[T] = object ## Private selected children preserve genuine source, geometry, Merkle and crypto causes.
    case status: AvailabilityTransferError
    of None: completed: T
    of SourceFailure: sourceReason: AvailabilityCommitmentError
    of GeometryFailure: geometryReason: ErasureLayoutError
    of MerkleFailure: merkleReason: AvailabilityMerkleError
    of BackendFailure: cryptoReason: CryptoError
    else: discard # Default/simple errors own no unrelated child or accepted payload.
  TransferData = ref object ## Source-free acyclic storage remains valid after every originating report/lease has retired.
    specifier: AvailabilitySpecifier
    request: AvailabilityRequest
    bundle, segments, proof: seq[byte]
  PreparedAvailabilityTransfer* = object ## Wire-ready construction is not remote verification or canonical report authority.
    data: nil TransferData
  VerifiedAvailabilityTransfer* = object ## Only complete verification against independently selected root/coordinates constructs this handle.
    data: nil TransferData
  TransferShape = object ## Every extent and hash-stage budget is derived from bounded expected metadata before extraction.
    geometry: ErasureGeometry
    validators, rows, width, shard, row: int
    outerTree, outerPath, innerTree, innerPath: AvailabilityMerkleWork
    proofBytes: int
func error*[T](outcome: AvailabilityTransferResult[T]): AvailabilityTransferError =
  ## Observe status without selecting mutable variant data.
  outcome.status
func value*[T](outcome: AvailabilityTransferResult[T]): T {.requires: outcome.status ==
    AvailabilityTransferError.None.} =
  ## Failed/default results cannot expose prepared or verified prefixes.
  outcome.completed
func sourceError*[T](outcome: AvailabilityTransferResult[
    T]): AvailabilityCommitmentError {.requires: outcome.status ==
    AvailabilityTransferError.SourceFailure.} =
  ## Preserve the actual failed original availability lookup.
  outcome.sourceReason
func geometryError*[T](outcome: AvailabilityTransferResult[
    T]): ErasureLayoutError {.requires: outcome.status ==
    AvailabilityTransferError.GeometryFailure.} =
  ## Preserve the actual GP geometry refusal.
  outcome.geometryReason
func merkleError*[T](outcome: AvailabilityTransferResult[
    T]): AvailabilityMerkleError {.requires: outcome.status ==
    AvailabilityTransferError.MerkleFailure.} =
  ## Preserve an exact non-backend trace refusal.
  outcome.merkleReason
func cryptoError*[T](outcome: AvailabilityTransferResult[
    T]): CryptoError {.requires: outcome.status == AvailabilityTransferError.BackendFailure.} =
  ## Only a real failed maintained primitive exposes its backend cause.
  outcome.cryptoReason
func failed[T](reason: AvailabilityTransferError): AvailabilityTransferResult[T] {.requires:
    reason notin {AvailabilityTransferError.None, AvailabilityTransferError.SourceFailure,
      AvailabilityTransferError.GeometryFailure, AvailabilityTransferError.MerkleFailure,
      AvailabilityTransferError.BackendFailure}.} =
  ## Simple failures contain only their selected reason.
  AvailabilityTransferResult[T](status: reason)
func propagated[T, U](outcome: AvailabilityTransferResult[U]): AvailabilityTransferResult[
    T] {.requires: outcome.status != AvailabilityTransferError.None.} =
  ## Propagate selected failure types without carrying a previously accepted data owner.
  case outcome.status
  of AvailabilityTransferError.SourceFailure: AvailabilityTransferResult[T](
      status: AvailabilityTransferError.SourceFailure, sourceReason: outcome.sourceReason)
  of AvailabilityTransferError.GeometryFailure: AvailabilityTransferResult[T](
      status: AvailabilityTransferError.GeometryFailure, geometryReason: outcome.geometryReason)
  of AvailabilityTransferError.MerkleFailure: AvailabilityTransferResult[T](
      status: AvailabilityTransferError.MerkleFailure, merkleReason: outcome.merkleReason)
  of AvailabilityTransferError.BackendFailure: AvailabilityTransferResult[T](
      status: AvailabilityTransferError.BackendFailure, cryptoReason: outcome.cryptoReason)
  of AvailabilityTransferError.None: AvailabilityTransferResult[T](
      status: AvailabilityTransferError.Uninitialized) # The checked precondition excludes this unreachable alternative.
  else: failed[T](outcome.status)
func merkleFailure[T, U](outcome: AvailabilityMerkleResult[U]): AvailabilityTransferResult[
    T] {.requires: outcome.error != AvailabilityMerkleError.None.} =
  ## Preserve the genuine backend child rather than flattening it into a structural proof error.
  if outcome.error == AvailabilityMerkleError.BackendFailure:
    return AvailabilityTransferResult[T](status: AvailabilityTransferError.BackendFailure,
        cryptoReason: outcome.cryptoError)
  AvailabilityTransferResult[T](status: AvailabilityTransferError.MerkleFailure,
      merkleReason: outcome.error)
proc copied(bytes: openArray[byte]): seq[byte] =
  ## Copy only a completely bounded retained/public byte range, never borrow external mutable storage.
  result = newSeq[byte](bytes.len)
  for index in 0..<result.len: result[index] = bytes[index]
func valid*(value: PreparedAvailabilityTransfer): bool =
  ## Defaults contain no constructed transfer, including no successful empty body.
  value.data != nil
func valid*(value: VerifiedAvailabilityTransfer): bool =
  ## A default handle grants no authenticated content.
  value.data != nil
func request*(value: PreparedAvailabilityTransfer): AvailabilityRequest {.requires: value.data != nil.} =
  ## Fixed copied coordinates remain bound to the root used during construction.
  let data = value.data
  assert data != nil
  data.request
func request*(value: VerifiedAvailabilityTransfer): AvailabilityRequest {.requires: value.data != nil.} =
  ## A verified payload cannot be rebound to another shard/row by mutating returned facts.
  let data = value.data
  assert data != nil
  data.request
func specifier*(value: PreparedAvailabilityTransfer): AvailabilitySpecifier {.requires: value.data != nil.} =
  ## This original commitment is distinct from remote/canonical inclusion authority.
  let data = value.data
  assert data != nil
  data.specifier
func specifier*(value: VerifiedAvailabilityTransfer): AvailabilitySpecifier {.requires: value.data != nil.} =
  ## The independent expected descriptor is retained with its exact authenticated content.
  let data = value.data
  assert data != nil
  data.specifier
proc bundleShard*(value: PreparedAvailabilityTransfer): seq[byte] {.requires: value.data != nil.} =
  ## Return an independent copy; segment-only transfers deliberately have an empty bundle field.
  let data = value.data
  assert data != nil
  copied(data.bundle)
proc bundleShard*(value: VerifiedAvailabilityTransfer): seq[byte] {.requires: value.data != nil.} =
  ## An independent verified byte copy cannot mutate retained authenticated content.
  let data = value.data
  assert data != nil
  copied(data.bundle)
proc segmentShards*(value: PreparedAvailabilityTransfer): seq[byte] {.requires: value.data != nil.} =
  ## Distribution has ordered rows, segment mode one row, and audit mode no segment data.
  let data = value.data
  assert data != nil
  copied(data.segments)
proc segmentShards*(value: VerifiedAvailabilityTransfer): seq[byte] {.requires: value.data != nil.} =
  ## Copy the exact authenticated ordered row payload.
  let data = value.data
  assert data != nil
  copied(data.segments)
proc justification*(value: PreparedAvailabilityTransfer): seq[byte] {.requires: value.data != nil.} =
  ## Native output freezes independent exact NP tagged proof bytes.
  let data = value.data
  assert data != nil
  copied(data.proof)
proc justification*(value: VerifiedAvailabilityTransfer): seq[byte] {.requires: value.data != nil.} =
  ## An assurer may retain/forward this checked evidence without touching the original peer buffer.
  let data = value.data
  assert data != nil
  copied(data.proof)
func stageLimits(maximum: AvailabilityMerkleLimits,
    work: AvailabilityMerkleWork): AvailabilityMerkleLimits =
  ## Aggregate precharge happens first; each child then receives only its own exact hash/call allowance.
  AvailabilityMerkleLimits(bytes: maximum.bytes, hashes: ElementLimit(work.hashes),
      hashBytes: ByteLimit(work.hashBytes))
func combined(a, b: AvailabilityMerkleWork): AvailabilityMerkleWork =
  ## Both terms are derived from hard bounded geometry; their sums remain below ten MiB of hash work and 4143 calls.
  AvailabilityMerkleWork(hashes: a.hashes+b.hashes, hashBytes: a.hashBytes+b.hashBytes)
func admitted(work: AvailabilityMerkleWork, bytes: uint64, limits: AvailabilityMerkleLimits): bool =
  ## No allocation/hash may precede complete independent memory, call and preimage caps.
  bytes <= uint64(limits.bytes) and work.hashes <= uint64(limits.hashes) and work.hashBytes <=
      uint64(limits.hashBytes)
proc shape(expected: AvailabilitySpecifier, request: AvailabilityRequest): AvailabilityTransferResult[
    TransferShape] =
  ## Reject untrusted dimensions/coordinates before narrowing, multiplication, slicing or protocol-specific extraction.
  if request.root.bytes != expected.erasureRoot.bytes: return failed[TransferShape](
      AvailabilityTransferError.RootMismatch)
  let length = uint64(uint32(expected.bundleLength))
  let exports = uint64(uint16(expected.segmentCount))
  if length == 0 or length > MaxAvailabilityBundleBytes or exports > 3072:
    return failed[TransferShape](AvailabilityTransferError.InvalidSpecifier)
  let geometry = erasureGeometry(expected.bundleLength, expected.erasureShards)
  if geometry.error != ErasureLayoutError.None:
    return AvailabilityTransferResult[TransferShape](
        status: AvailabilityTransferError.GeometryFailure, geometryReason: geometry.error)
  let n = int(uint16(expected.erasureShards))
  let rows = int(exports+(exports+63) div 64)
  if uint64(request.shard) >= uint64(n): return failed[TransferShape](
      AvailabilityTransferError.InvalidIndex)
  if request.kind == AvailabilityTransferKind.Segment:
    if uint64(request.row) >= uint64(rows): return failed[TransferShape](
        AvailabilityTransferError.InvalidIndex)
  elif uint64(request.row) != 0:
    return failed[TransferShape](AvailabilityTransferError.InvalidIndex)
  let width = int(geometry.value.segmentChunkBytes)
  let shard = int(uint64(request.shard))
  let row = int(uint64(request.row))
  let outer = availabilityTraceWork(64, n, shard, 1)
  if outer.error != AvailabilityMerkleError.None: return merkleFailure[TransferShape,
      AvailabilityMerkleWork](outer)
  let outerTree = availabilityTreeWork(64, n)
  if outerTree.error != AvailabilityMerkleError.None: return merkleFailure[TransferShape,
      AvailabilityMerkleWork](outerTree)
  let innerTree = availabilityTreeWork(width, rows)
  if innerTree.error != AvailabilityMerkleError.None: return merkleFailure[TransferShape,
      AvailabilityMerkleWork](innerTree)
  var completed = TransferShape(geometry: geometry.value, validators: n, rows: rows, width: width,
    shard: shard, row: row, outerPath: outer.value, outerTree: outerTree.value,
    innerTree: innerTree.value, proofBytes: int(outer.value.proofBytes))
  if request.kind == AvailabilityTransferKind.Audit:
    completed.proofBytes += 33 # NP appends one tagged segment-shard root.
  elif request.kind == AvailabilityTransferKind.Segment:
    let inner = availabilityTraceWork(width, rows, row, 2)
    if inner.error != AvailabilityMerkleError.None: return merkleFailure[TransferShape,
        AvailabilityMerkleWork](inner)
    completed.innerPath = inner.value
    completed.proofBytes += 33+int(inner.value.proofBytes)
  AvailabilityTransferResult[TransferShape](status: AvailabilityTransferError.None,
      completed: completed)
func constructionWork(shape: TransferShape, kind: AvailabilityTransferKind): AvailabilityMerkleWork =
  ## Trace construction plus leaf reconstruction has whole-tree work; bundle hashing is charged separately where data is present.
  result = shape.outerTree
  if kind == AvailabilityTransferKind.Segment: result = combined(result, shape.innerTree)
  else:
    result = combined(result, AvailabilityMerkleWork(hashes: 1,
        hashBytes: shape.geometry.bundleChunkBytes))
    if kind == AvailabilityTransferKind.Distribution: result = combined(result, shape.innerTree)
func verificationWork(shape: TransferShape, kind: AvailabilityTransferKind): AvailabilityMerkleWork =
  ## Received evidence needs selected-path hashes only, plus full segment-row root work for distribution.
  result = shape.outerPath
  if kind == AvailabilityTransferKind.Segment: result = combined(result, shape.innerPath)
  else:
    result = combined(result, AvailabilityMerkleWork(hashes: 1,
        hashBytes: shape.geometry.bundleChunkBytes))
    if kind == AvailabilityTransferKind.Distribution: result = combined(result, shape.innerTree)
func constructionBytes(shape: TransferShape, kind: AvailabilityTransferKind): uint64 =
  ## Include flat source extraction, all temporary/final proof copies and the largest per-row extraction before allocating.
  result = uint64(shape.validators)*64+uint64(shape.proofBytes)*3
  if kind != AvailabilityTransferKind.Segment: result += shape.geometry.bundleChunkBytes
  if kind != AvailabilityTransferKind.Audit: result += uint64(shape.rows*shape.width+shape.width)
  if kind == AvailabilityTransferKind.Segment: result += uint64(shape.width)
proc prepareAvailabilityTransfer*(source: AvailabilityCommitment, request: AvailabilityRequest,
    limits: AvailabilityMerkleLimits): AvailabilityTransferResult[PreparedAvailabilityTransfer] =
  ## Run under the managed graph lease; returned wire/data owners contain no original source alias or native pointer.
  let described = source.availabilityInfo
  if described.error != AvailabilityCommitmentError.None:
    return AvailabilityTransferResult[PreparedAvailabilityTransfer](
        status: AvailabilityTransferError.SourceFailure, sourceReason: described.error)
  let planned = shape(described.value.specifier, request)
  if planned.error != AvailabilityTransferError.None: return propagated[
      PreparedAvailabilityTransfer, TransferShape](planned)
  let shape = planned.value
  if not admitted(constructionWork(shape, request.kind), constructionBytes(shape, request.kind), limits):
    return failed[PreparedAvailabilityTransfer](AvailabilityTransferError.LimitExceeded)
  let exports = source.availabilitySource.value
  let exportInfo = exports.exportErasureInfo.value
  if exportInfo.rows != uint64(shape.rows) or exportInfo.geometry.segmentChunkBytes != uint64(shape.width):
    return failed[PreparedAvailabilityTransfer](AvailabilityTransferError.InvalidSpecifier)
  var pairs = newSeq[byte](shape.validators*64)
  for index in 0..<shape.validators:
    # Existing independently computed commitments supply actual leaf pairs, not peer/caller-provided substitute roots.
    let selected = source.availabilityShard(ErasureShardIndex(uint64(index))).value
    for position in 0..<32:
      pairs[index*64+position] = array[32, byte](selected.bundleHash)[position]
      pairs[index*64+32+position] = array[32, byte](selected.exportRoot)[position]
  let outer = prepareAvailabilityTrace(pairs, 64, shape.validators, shape.shard, 1, stageLimits(
      limits, shape.outerTree))
  if outer.error != AvailabilityMerkleError.None: return merkleFailure[PreparedAvailabilityTransfer,
      AvailabilityTrace](outer)
  if array[32, byte](outer.value.root) != described.value.specifier.erasureRoot.bytes:
    return failed[PreparedAvailabilityTransfer](AvailabilityTransferError.RootMismatch)
  var bundle, rows, proof: seq[byte] = @[]
  let selected = source.availabilityShard(request.shard).value
  if request.kind != AvailabilityTransferKind.Segment:
    bundle = exports.exportErasureSource.value.bundleErasureChunk(request.shard).value
    let digest = blake2b256(bundle)
    if digest.error != CryptoError.None:
      return AvailabilityTransferResult[PreparedAvailabilityTransfer](
          status: AvailabilityTransferError.BackendFailure, cryptoReason: digest.error)
    if array[32, byte](digest.value) != array[32, byte](selected.bundleHash):
      return failed[PreparedAvailabilityTransfer](AvailabilityTransferError.RootMismatch)
  if request.kind != AvailabilityTransferKind.Audit:
    rows = newSeq[byte](shape.rows*shape.width)
    for index in 0..<shape.rows:
      let chunk = exports.exportErasureChunk(request.shard, ExportErasureIndex(uint64(index))).value
      for position in 0..<shape.width: rows[index*shape.width+position] = chunk[position]
  proof = newSeq[byte](shape.proofBytes)
  let outerBytes = outer.value.bytes
  for position in 0..<outerBytes.len: proof[position] = outerBytes[position]
  if request.kind == AvailabilityTransferKind.Audit:
    proof[outerBytes.len] = 0
    for position in 0..<32: proof[outerBytes.len+1+position] = array[32, byte](selected.exportRoot)[position]
  elif request.kind == AvailabilityTransferKind.Segment:
    proof[outerBytes.len] = 0
    for position in 0..<32: proof[outerBytes.len+1+position] = array[32, byte](selected.bundleHash)[position]
    let inner = prepareAvailabilityTrace(rows, shape.width, shape.rows, shape.row, 2, stageLimits(
        limits, shape.innerTree))
    if inner.error != AvailabilityMerkleError.None: return merkleFailure[
        PreparedAvailabilityTransfer, AvailabilityTrace](inner)
    if array[32, byte](inner.value.root) != array[32, byte](selected.exportRoot):
      return failed[PreparedAvailabilityTransfer](AvailabilityTransferError.RootMismatch)
    let innerBytes = inner.value.bytes
    for position in 0..<innerBytes.len: proof[outerBytes.len+33+position] = innerBytes[position]
    rows = copied(rows.toOpenArray(shape.row*shape.width, (shape.row+1)*shape.width-1))
  else:
    let root = availabilityMerkleRoot(rows, shape.width, shape.rows, stageLimits(limits,
        shape.innerTree))
    if root.error != AvailabilityMerkleError.None: return merkleFailure[
        PreparedAvailabilityTransfer, Blake2bHash](root)
    if array[32, byte](root.value) != array[32, byte](selected.exportRoot):
      return failed[PreparedAvailabilityTransfer](AvailabilityTransferError.RootMismatch)
  AvailabilityTransferResult[PreparedAvailabilityTransfer](status: AvailabilityTransferError.None,
    completed: PreparedAvailabilityTransfer(data: TransferData(specifier: described.value.specifier,
      request: request, bundle: bundle, segments: rows, proof: proof)))
proc verifyAvailabilityTransfer*(expected: AvailabilitySpecifier, request: AvailabilityRequest,
    bundle, segments, proof: openArray[byte],
    limits: AvailabilityMerkleLimits): AvailabilityTransferResult[VerifiedAvailabilityTransfer] =
  ## Independent expected metadata/coordinates and every exact message extent precede hashing or retained output copies.
  let planned = shape(expected, request)
  if planned.error != AvailabilityTransferError.None: return propagated[
      VerifiedAvailabilityTransfer, TransferShape](planned)
  let shape = planned.value
  let bundleBytes = if request.kind == AvailabilityTransferKind.Segment: 0'u64 else: shape.geometry.bundleChunkBytes
  let segmentBytes = if request.kind == AvailabilityTransferKind.Audit: 0'u64
    elif request.kind == AvailabilityTransferKind.Segment: uint64(shape.width)
    else: uint64(shape.rows*shape.width)
  if uint64(bundle.len) != bundleBytes or uint64(segments.len) != segmentBytes:
    return failed[VerifiedAvailabilityTransfer](AvailabilityTransferError.InvalidPayload)
  if proof.len != shape.proofBytes: return failed[VerifiedAvailabilityTransfer](
      AvailabilityTransferError.InvalidProof)
  let bytes = bundleBytes+segmentBytes+uint64(proof.len)
  if not admitted(verificationWork(shape, request.kind), bytes*2, limits):
    return failed[VerifiedAvailabilityTransfer](AvailabilityTransferError.LimitExceeded)
  let outerBytes = int(shape.outerPath.proofBytes)
  var pair = default(array[64, byte])
  if request.kind == AvailabilityTransferKind.Segment:
    # The explicit middle bundle hash joins the reconstructed row root before outer-root authentication.
    if proof[outerBytes] != 0: return failed[VerifiedAvailabilityTransfer](
        AvailabilityTransferError.InvalidProof)
    for position in 0..<32: pair[position] = proof[outerBytes+1+position]
    let root = reconstructAvailabilityTrace(segments, proof.toOpenArray(outerBytes+33, proof.len-1),
      shape.width, shape.rows, shape.row, 2, stageLimits(limits, shape.innerPath))
    if root.error != AvailabilityMerkleError.None: return merkleFailure[
        VerifiedAvailabilityTransfer, Blake2bHash](root)
    for position in 0..<32: pair[32+position] = array[32, byte](root.value)[position]
  else:
    let digest = blake2b256(bundle)
    if digest.error != CryptoError.None:
      return AvailabilityTransferResult[VerifiedAvailabilityTransfer](
          status: AvailabilityTransferError.BackendFailure, cryptoReason: digest.error)
    for position in 0..<32: pair[position] = array[32, byte](digest.value)[position]
    if request.kind == AvailabilityTransferKind.Audit:
      if proof[outerBytes] != 0: return failed[VerifiedAvailabilityTransfer](
          AvailabilityTransferError.InvalidProof)
      for position in 0..<32: pair[32+position] = proof[outerBytes+1+position]
      if shape.rows == 0:
        for position in 32..<64:
          if pair[position] != 0: return failed[VerifiedAvailabilityTransfer](
              AvailabilityTransferError.RootMismatch)
    else:
      let root = availabilityMerkleRoot(segments, shape.width, shape.rows, stageLimits(limits,
          shape.innerTree))
      if root.error != AvailabilityMerkleError.None: return merkleFailure[
          VerifiedAvailabilityTransfer, Blake2bHash](root)
      for position in 0..<32: pair[32+position] = array[32, byte](root.value)[position]
  let checked = verifyAvailabilityTrace(Blake2bHash(expected.erasureRoot.bytes), pair,
    proof.toOpenArray(0, outerBytes-1), 64, shape.validators, shape.shard, 1, stageLimits(limits,
        shape.outerPath))
  if checked.error != AvailabilityMerkleError.None: return merkleFailure[
      VerifiedAvailabilityTransfer, Blake2bHash](checked)
  AvailabilityTransferResult[VerifiedAvailabilityTransfer](status: AvailabilityTransferError.None,
    completed: VerifiedAvailabilityTransfer(data: TransferData(specifier: expected,
      request: request,
      bundle: copied(bundle), segments: copied(segments), proof: copied(proof))))
