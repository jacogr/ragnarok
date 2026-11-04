# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Recover one original export and its GP paged-proof row, then authenticate against a source-bound canonical report.
## Detached erasure arithmetic alone never grants import authority; all proof work belongs on the managed CPU worker.
import ../chain/import_catalog
import ../codec/[bounded, natural]
from ../codec/work/package import ImportIndex
from ../codec/work/report import BundleLength, SegmentRoot
from ../pvm/host/fetch import FetchSegment
import ../crypto/primitives
import ../state/erasure/[layout, words]
import "../state/import/justification" as import_proof

type
  ImportRecoveryError* {.pure.} = enum ## Failed/default recovery exposes no segment, proof page or verified prefix.
    Uninitialized, None, InvalidSource, InvalidIndex, InvalidPayload, LimitExceeded,
      ReconstructionMismatch, RecoveryFailure, ProofFailure, BackendFailure
  ImportRecoveryLimits* = object ## Aggregate logical payload/workspace, field products and hashes are independent operator ceilings.
    bytes*, hashBytes*: ByteLimit
    products*: FieldProductLimit
    hashes*: ElementLimit
    proof*: ImportJustificationLimits
  ImportRecoveryResult* = object ## Only complete original-root verification exposes a usable import owner.
    case status: ImportRecoveryError
    of None: completed: VerifiedImport
    of RecoveryFailure: recoveryReason: ErasureWordError
    of ProofFailure: proofReason: ImportJustificationError
    of BackendFailure: cryptoReason: CryptoError
    else: discard # A reason alone cannot authorize any reconstructed byte prefix.
func error*(outcome: ImportRecoveryResult): ImportRecoveryError =
  ## Inspect the selected stage without writable variant fields.
  outcome.status
func value*(outcome: ImportRecoveryResult): VerifiedImport {.requires: outcome.status ==
    ImportRecoveryError.None.} =
  ## Extract only a complete segment/proof authenticated to the original canonical source.
  outcome.completed
func recoveryError*(outcome: ImportRecoveryResult): ErasureWordError {.requires: outcome.status ==
    ImportRecoveryError.RecoveryFailure.} =
  ## Preserve the actual threshold decoder's cause rather than manufacturing a crypto failure.
  outcome.recoveryReason
func proofError*(outcome: ImportRecoveryResult): ImportJustificationError {.requires: outcome.status ==
    ImportRecoveryError.ProofFailure.} =
  ## Preserve the genuine final GP verifier refusal.
  outcome.proofReason
func cryptoError*(outcome: ImportRecoveryResult): CryptoError {.requires: outcome.status ==
    ImportRecoveryError.BackendFailure.} =
  ## Only an actual maintained primitive failure carries a backend child.
  outcome.cryptoReason
func failure(reason: ImportRecoveryError): ImportRecoveryResult {.requires: reason notin {
    ImportRecoveryError.None, ImportRecoveryError.RecoveryFailure, ImportRecoveryError.ProofFailure,
    ImportRecoveryError.BackendFailure}.} =
  ## Local structural/resource refusal carries no unrelated child or successful prefix.
  ImportRecoveryResult(status: reason)
proc recoverImport*(source: ReportedImport, index: ImportIndex, segmentChunks,
    pageChunks: openArray[byte], indices: openArray[ErasureShardIndex],
    limits: ImportRecoveryLimits): ImportRecoveryResult =
  ## Borrow stable paired threshold rows synchronously; preflight complete arithmetic and paged-proof geometry before hashing.
  let described = source.reportedImportInfo
  if described.error != ImportCatalogError.None: return failure(ImportRecoveryError.InvalidSource)
  let specifier = described.value.specifier
  let ordinal = int(uint16(index))
  let count = int(uint16(specifier.segmentCount))
  if ordinal >= count or ordinal >= 3072: return failure(ImportRecoveryError.InvalidIndex)
  let geometry = erasureGeometry(BundleLength(4104), specifier.erasureShards)
  if geometry.error != ErasureLayoutError.None: return failure(ImportRecoveryError.InvalidSource)
  if uint64(indices.len) != geometry.value.originalShards or segmentChunks.len != 4104 or
      pageChunks.len != 4104:
    return failure(ImportRecoveryError.InvalidPayload)
  var depth = 0
  var leaves = 1
  while leaves < count:
    leaves *= 2 # At most4096 leaves: the source descriptor and ordinal were bounded before multiplication.
    inc depth
  let levels = max(0, depth-6)
  let localDepth = min(depth, 6)
  let capacity = 1 shl localDepth
  let pageIndex = ordinal div 64
  let pageCount = min(64, count-pageIndex*64)
  let hashes = uint64(capacity+depth+1)
  let hashBytes = 8216'u64+uint64(capacity-1+depth)*68
  if hashes > uint64(limits.hashes) or hashBytes > uint64(limits.hashBytes):
    return failure(ImportRecoveryError.LimitExceeded)
  let proofBytes = 4104'u64+uint64(depth)*32
  let proofHashBytes = 4108'u64+uint64(depth)*68
  if uint64(depth) > uint64(limits.proof.siblings): return failure(
      ImportRecoveryError.LimitExceeded)
  if proofBytes > uint64(limits.proof.payloadBytes): return failure(
      ImportRecoveryError.LimitExceeded)
  if proofHashBytes > uint64(limits.proof.hashBytes): return failure(
      ImportRecoveryError.LimitExceeded)
  # Fixed logical scratch includes detached row copies, leaf scratch/output, tree, both paths and hash preimages.
  const FixedBytes = uint64(2*4104+2*4104+128*32+2*12*32+2*4108+2*68)
  if uint64(limits.bytes) < FixedBytes: return failure(ImportRecoveryError.LimitExceeded)
  let arithmetic = ErasureWordLimits(bytes: ByteLimit((uint64(limits.bytes)-FixedBytes) div 2),
    products: FieldProductLimit(uint64(limits.products) div 2))
  # Both rows have identical geometry/indices and exact equal work, so the half-caps preflight their combined arithmetic.
  let segment = recoverErasureChunks(segmentChunks, indices, BundleLength(4104),
      specifier.erasureShards, arithmetic)
  if segment.error != ErasureWordError.None:
    return ImportRecoveryResult(status: ImportRecoveryError.RecoveryFailure,
        recoveryReason: segment.error)
  let page = recoverErasureChunks(pageChunks, indices, BundleLength(4104), specifier.erasureShards, arithmetic)
  if page.error != ErasureWordError.None:
    return ImportRecoveryResult(status: ImportRecoveryError.RecoveryFailure,
        recoveryReason: page.error)
  let raw = segment.value.recoveredBytes.value
  let proofPage = page.value.recoveredBytes.value
  var cursor = 0
  let prefix = decode(proofPage)
  if not prefix.ok: return failure(ImportRecoveryError.ReconstructionMismatch)
  if uint64(prefix.value) != uint64(levels): return failure(
      ImportRecoveryError.ReconstructionMismatch)
  cursor += prefix.consumed
  let pathStart = cursor
  cursor += levels*32 # Six upper siblings and two bounded prefixes fit the fixed4104-byte original proof page.
  if cursor >= proofPage.len: return failure(ImportRecoveryError.ReconstructionMismatch)
  let listed = decode(proofPage.toOpenArray(cursor, proofPage.high))
  if not listed.ok: return failure(ImportRecoveryError.ReconstructionMismatch)
  if uint64(listed.value) != uint64(pageCount): return failure(
      ImportRecoveryError.ReconstructionMismatch)
  cursor += listed.consumed
  let leafStart = cursor
  cursor += pageCount*32
  if cursor > proofPage.len: return failure(ImportRecoveryError.ReconstructionMismatch)
  for position in cursor..<proofPage.len:
    # GP zero-padding has a unique representation; nonzero unused proof-page suffixes cannot disappear during reconstruction.
    if proofPage[position] != 0: return failure(ImportRecoveryError.ReconstructionMismatch)
  var leaf = default(array[4104, byte])
  var leafPreimage = default(array[4108, byte])
  leafPreimage[0] = byte('l')
  leafPreimage[1] = byte('e')
  leafPreimage[2] = byte('a')
  leafPreimage[3] = byte('f')
  for position in 0..<4104:
    leaf[position] = raw[position]
    leafPreimage[4+position] = raw[position]
  let leafHash = blake2b256(leafPreimage)
  if leafHash.error != CryptoError.None:
    return ImportRecoveryResult(status: ImportRecoveryError.BackendFailure,
        cryptoReason: leafHash.error)
  let expectedLeaf = leafStart+(ordinal mod 64)*32
  for position in 0..<32:
    if proofPage[expectedLeaf+position] != array[32, byte](leafHash.value)[position]:
      return failure(ImportRecoveryError.ReconstructionMismatch)
  var tree = default(array[128, SegmentRoot])
  for local in 0..<pageCount:
    # Zero padding leaves remain the GP zero hash; only genuine recorded leaf hashes are copied into the local constant-depth tree.
    for position in 0..<32: tree[capacity+local].bytes[position] = proofPage[
        leafStart+local*32+position]
  var node = capacity-1
  var preimage = default(array[68, byte])
  preimage[0] = byte('n')
  preimage[1] = byte('o')
  preimage[2] = byte('d')
  preimage[3] = byte('e')
  while node > 0:
    # Rebuild each local page-tree node once; original-root verification below binds upper and local siblings together.
    for position in 0..<32:
      preimage[4+position] = tree[node*2].bytes[position]
      preimage[36+position] = tree[node*2+1].bytes[position]
    let hash = blake2b256(preimage)
    if hash.error != CryptoError.None:
      return ImportRecoveryResult(status: ImportRecoveryError.BackendFailure,
          cryptoReason: hash.error)
    tree[node].bytes = array[32, byte](hash.value)
    dec node
  var path = newSeq[SegmentRoot](depth)
  for level in 0..<levels:
    for position in 0..<32: path[level].bytes[position] = proofPage[pathStart+level*32+position]
  var selected = 1
  for level in 0..<localDepth:
    # Root-first local siblings match the original export ordinal's low six bits, including partial final pages.
    let direction = ((ordinal mod 64) shr (localDepth-level-1)) and 1
    path[levels+level] = tree[selected*2+(1-direction)]
    selected = selected*2+direction
  let verified = verifyImportSegment(specifier.segmentRoot, index, FetchSegment(leaf), path, limits.proof)
  if verified.error != ImportJustificationError.None:
    return ImportRecoveryResult(status: ImportRecoveryError.ProofFailure,
        proofReason: verified.error)
  ImportRecoveryResult(status: ImportRecoveryError.None, completed: verified.value)
