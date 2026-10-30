# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_export_erasure_arc_release"}

## Independent complete export/page erasure bytes, original provenance, budget preflight and ownership.

import std/[assertions, syncio]
import "../../../src/state/export/erasure" as export_erasure
import "../../../src/state/export/commitment" as export_commitment
import ../../../src/state/bundle_erasure
import ../../../src/state/erasure/words as erasure_words
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
import ../../../src/pvm/host/fetch as host_fetch
import ../../../src/crypto/primitives
import ../../support/[pvm_export_erasure, pvm_export_erasure_vectors, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashing after original execution to verify preflight and commitment failure boundaries.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Inspect actual primitive calls; coding itself must add none to the export-tree work.
proc expect[T](outcome: ExportErasureResult[T], reason: ExportErasureError) =
  ## Compare exact reasons without selecting incomplete output or source owners.
  assert outcome.error == reason, "export erasure reason"
proc verify(source: BundleErasure, kind: int, root, expected: array[32, byte]): ExportErasure =
  ## Compare the complete validator-major combined sequence with independent full-wire witnesses.
  reset(0)
  let done = prepareExportErasure(source, exportErasureLimits()).value
  let info = done.exportErasureInfo.value
  let tree = done.exportErasureCommitment.value.commitmentInfo.value
  let count = int(uint16(info.exports))
  var capacity = 1
  while capacity < count: capacity *= 2 # Tree normalization counts absent leaves as zero hashes.
  assert hashes() == cint(count+capacity-1), "only the original export tree is hashed"
  assert info.root.bytes == root, "independent export root"
  assert info.rows == uint64(count)+info.pages, "data followed by proof pages"
  assert info.pages == uint64((count+63) div 64), "canonical proof page count"
  assert info.packageHash.bytes == source.bundleErasureInfo.value.packageHash.bytes, "original package identity"
  var joined: seq[byte] = @[]
  # All chunks are ordered by validator, then original exports and proof pages, with no extra row framing.
  for shard in 0..<int(uint16(info.geometry.shards)):
    for row in 0..<int(info.rows):
      let chunk = done.exportErasureChunk(ErasureShardIndex(uint64(shard)), ExportErasureIndex(
          uint64(row))).value
      assert chunk.len == int(info.geometry.segmentChunkBytes), "fixed complete data/page chunk"
      for octet in chunk: joined.add(octet)
  assert uint64(joined.len) == info.retainedBytes, "complete encoded output length"
  assert array[32, byte](blake2b256(joined).value) == expected, "independent complete export/page encoded bytes"
  # Concatenating original chunks reconstructs all 4104 bytes of every normalized data segment and canonical proof page.
  for row in 0..<int(info.rows):
    var bytes = default(array[4104, byte])
    if row < count:
      if row == 0 and (kind == 1 or kind == 3):
        bytes[0] = 11 # Only the successful item's export survives normalization.
        bytes[1] = 12
        bytes[2] = 13
    else:
      bytes = array[4104, byte](done.exportErasureCommitment.value.commitmentPage(ExportPageIndex(
          uint64(row-count))).value)
    var cursor = 0
    for shard in 0..<int(info.geometry.originalShards):
      for octet in done.exportErasureChunk(ErasureShardIndex(uint64(shard)), ExportErasureIndex(
          uint64(row))).value:
        assert octet == bytes[cursor], "systematic data/page reconstruction"
        inc cursor
    assert cursor == 4104, "fixed segment reconstruction without padding"
  var exact = exportErasureLimits()
  exact.bytes = ByteLimit(info.retainedBytes+info.workspaceBytes)
  exact.products = FieldProductLimit(info.products)
  exact.commitment.exports = ElementLimit(count)
  exact.commitment.nodes = ElementLimit(tree.nodes)
  exact.commitment.hashBytes = ByteLimit(tree.hashBytes)
  expect(prepareExportErasure(source, exact), ExportErasureError.None)
  if info.rows > 0:
    exact.bytes = ByteLimit(uint64(exact.bytes)-1)
    expect(prepareExportErasure(source, exact), ExportErasureError.LimitExceeded)
    exact.bytes = ByteLimit(uint64(exact.bytes)+1)
    exact.products = FieldProductLimit(info.products-1)
    expect(prepareExportErasure(source, exact), ExportErasureError.LimitExceeded)
  exact = exportErasureLimits()
  exact.commitment.nodes = ElementLimit(tree.nodes-1)
  expect(prepareExportErasure(source, exact), ExportErasureError.LimitExceeded)
  expect(done.exportErasureChunk(ErasureShardIndex(uint64(uint16(info.geometry.shards))),
      ExportErasureIndex(0)), ExportErasureError.InvalidIndex)
  expect(done.exportErasureChunk(ErasureShardIndex(0), ExportErasureIndex(info.rows)),
      ExportErasureError.InvalidIndex)
  expect(done.exportErasureChunk(ErasureShardIndex(high(uint64)), ExportErasureIndex(high(uint64))),
      ExportErasureError.InvalidIndex)
  assert done.exportErasureSource.value.bundleErasureInfo.value.packageHash.bytes ==
      info.packageHash.bytes, "retained exact bundle source"
  done
let emptySource = exportBundle(0, 6)
let empty = verify(emptySource, 0, EmptyRoot, EmptyHash)
let emptyInfo = empty.exportErasureInfo.value
assert emptyInfo.rows == 0, "empty original exports have no proof rows"
assert emptyInfo.products == 0, "empty encoding performs no field work"
assert emptyInfo.workspaceBytes == 0, "empty encoding needs no coding workspace"
assert emptyInfo.retainedBytes == 0, "empty encoding has no output bytes"
let singleSource = exportBundle(1)
let single = verify(singleSource, 1, SingleRoot, SingleHash)
assert single.exportErasureChunk(ErasureShardIndex(342), ExportErasureIndex(0)).value ==
    @SingleData, "single explicit data parity"
assert single.exportErasureChunk(ErasureShardIndex(1022), ExportErasureIndex(1)).value ==
    @SinglePage, "single explicit page parity"
assert single.exportErasureInfo.value.products == 3676476, "independent twelve-column field work"
assert single.exportErasureInfo.value.workspaceBytes == 4438, "independent aggregate coding workspace"
let mixed = verify(exportBundle(3), 3, MixedRoot, MixedHash)
assert mixed.exportErasureChunk(ErasureShardIndex(342), ExportErasureIndex(0)).value == @MixedData, "mixed data parity"
assert mixed.exportErasureChunk(ErasureShardIndex(1022), ExportErasureIndex(3)).value == @MixedPage, "mixed page parity"
let paged = verify(exportBundle(65, 6), 65, PagedRoot, PagedHash)
assert paged.exportErasureInfo.value.rows == 67, "65 exports precede two proof pages"
assert paged.exportErasureInfo.value.products == 4674456, "independent page-boundary field work"
# Metadata and extracted bytes cannot mutate retained roots, identities or original encoded chunks.
var copied = single.exportErasureChunk(ErasureShardIndex(1022), ExportErasureIndex(1)).value
copied[0] = copied[0] xor 1
assert single.exportErasureChunk(ErasureShardIndex(1022), ExportErasureIndex(1)).value ==
    @SinglePage, "chunk copy isolation"
var facts = single.exportErasureInfo.value
facts.root.bytes[0] = facts.root.bytes[0] xor 1
facts.geometry.originalShards = 0
assert single.exportErasureInfo.value.root.bytes == SingleRoot, "root copy isolation"
assert single.exportErasureInfo.value.geometry.originalShards == 342, "geometry copy isolation"
expect(default(ExportErasure).exportErasureInfo, ExportErasureError.Uninitialized)
expect(default(ExportErasure).exportErasureSource, ExportErasureError.Uninitialized)
expect(default(ExportErasure).exportErasureCommitment, ExportErasureError.Uninitialized)
expect(default(ExportErasure).exportErasureChunk(ErasureShardIndex(0), ExportErasureIndex(0)),
    ExportErasureError.Uninitialized)
expect(prepareExportErasure(default(BundleErasure), ExportErasureLimits()),
    ExportErasureError.InvalidSource)
expect(default(ExportErasureResult[ExportErasure]), ExportErasureError.Uninitialized)
# Complete coding limits fail before tree hashing; empty trees remain valid when the backend is refused.
reset(1)
var cap = exportErasureLimits()
cap.bytes = ByteLimit(0)
expect(prepareExportErasure(singleSource, cap), ExportErasureError.LimitExceeded)
cap = exportErasureLimits()
cap.products = FieldProductLimit(0)
expect(prepareExportErasure(singleSource, cap), ExportErasureError.LimitExceeded)
cap = exportErasureLimits()
cap.commitment.nodes = ElementLimit(0)
expect(prepareExportErasure(singleSource, cap), ExportErasureError.LimitExceeded)
expect(prepareExportErasure(emptySource, exportErasureLimits()), ExportErasureError.None)
assert hashes() == 0, "all preflight refusals precede hashing"
expect(prepareExportErasure(singleSource, exportErasureLimits()),
    ExportErasureError.CommitmentFailure)
reset(0)
proc detached(): ExportErasure =
  ## Retain export encoding and original executed source after local construction handles retire.
  prepareExportErasure(exportBundle(0, 6), exportErasureLimits()).value
assert detached().exportErasureInfo.value.root.bytes == EmptyRoot, "detached source lifetime"
let cycleSource = exportBundle(1, 6)
proc cycle() =
  ## Release encoded data/pages, scalar workspaces, derived trees and refused candidates every iteration.
  let done = prepareExportErasure(cycleSource, exportErasureLimits()).value
  assert done.exportErasureChunk(ErasureShardIndex(5), ExportErasureIndex(1)).value.len == 1368, "ARC complete page parity"
  expect(prepareExportErasure(cycleSource, ExportErasureLimits()), ExportErasureError.LimitExceeded)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "export erasure ARC release"
recordArcRelease("pvm_export_erasure", 1000, before, after)
echo "PVM export erasure passed"
echo "ARC_RELEASE cycles=1000 unchanged"
