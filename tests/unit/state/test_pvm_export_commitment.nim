# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_export_commitment_arc_release"}

## Independent export roots/proof bytes, final-result selection, budget preflight and immutable ownership.

import std/[assertions, syncio]
import "../../../src/state/export/commitment" as export_commitment
import ../../../src/state/report/identity as report_identity
import ../../../src/state/authorized_refinement
import ../../../src/state/refinement/[digest as refinement_digest, report as refinement_report]
import ../../../src/codec/[bounded, composite, natural]
import ../../../src/codec/work/report as work_report
import ../../../src/pvm/host_fetch
import ../../../src/crypto/primitives
import ../../support/[pvm_export_commitment, pvm_export_vectors, pvm_report_results,
    pvm_refinement_outcome, arc_evidence]

proc hashPair(left, right: array[32, byte]): array[32, byte] =
  ## Test-only explicit node preimage supports independent bottom-up proof reconstruction.
  var bytes = @[byte('n'), byte('o'), byte('d'), byte('e')]
  for octet in left: bytes.add(octet)
  for octet in right: bytes.add(octet)
  array[32, byte](blake2b256(bytes).value)
proc verifyPage(proof: FetchSegment, page, count: int, expected: SegmentRoot) =
  ## Decode page framing and reconstruct the root bottom-up, independently of production heap addressing.
  let bytes = array[4104, byte](proof)
  let pathCount = decode(bytes).value
  let depth = int(uint64(pathCount))
  var cursor = 1
  var path: seq[array[32, byte]] = @[]
  for step in 0..<depth:
    var sibling = default(array[32, byte])
    for octet in 0..<32: sibling[octet] = bytes[cursor+octet]
    cursor += 32
    path.add(sibling)
  let leafCount = int(uint64(decode(bytes.toOpenArray(cursor, bytes.high)).value))
  inc cursor
  assert leafCount == min(64, count-page*64)
  var width = 1
  while width < count: width *= 2 # Reconstruct the page subtree's padded width, including shallow trees.
  width = min(64, width)
  var leaves = newSeq[array[32, byte]](width)
  for leaf in 0..<leafCount:
    for octet in 0..<32: leaves[leaf][octet] = bytes[cursor+octet]
    cursor += 32
  for offset in cursor..<4104: assert bytes[offset] == 0 # Zero-pad the proof segment, not its actual hash count.
  while leaves.len > 1:
    var parents: seq[array[32, byte]] = @[]
    for index in 0..<leaves.len div 2: parents.add(hashPair(leaves[index*2], leaves[index*2+1]))
    leaves = parents
  var root = leaves[0]
  var step = depth
  while step > 0:
    dec step
    let bit = (page shr (depth-step-1)) and 1
    root = if bit == 0: hashPair(root, path[step]) else: hashPair(path[step], root)
  assert root == expected.bytes
# Literal independent hash witnesses distinguish empty, actual zero-segment leaves and tree padding hashes.
for index, count in ZeroCounts:
  let source = zeroExportSource(uint64(count))
  let done = prepareExportCommitment(source, commitmentLimits()).value
  let info = done.commitmentInfo.value
  assert info.root.bytes == ZeroRoots[index]
  assert uint16(info.exports) == uint16(count)
  assert info.pages == uint64((count+63) div 64)
  assert done.commitmentSource.value.identityInfo.value.packageHash.bytes ==
      source.identityInfo.value.packageHash.bytes
  assert done.commitmentPage(ExportPageIndex(info.pages)).error ==
      ExportCommitmentError.InvalidIndex
  assert done.commitmentPage(ExportPageIndex(high(uint64))).error ==
      ExportCommitmentError.InvalidIndex
  if count > 0:
    let first = done.commitmentPage(ExportPageIndex(0)).value
    assert array[32, byte](blake2b256(array[4104, byte](first)).value) == FirstPages[index-1]
    for page in 0..<int(info.pages): verifyPage(done.commitmentPage(ExportPageIndex(uint64(
        page))).value, page, count, info.root)
    if count == 3072:
      assert array[32, byte](blake2b256(array[4104, byte](done.commitmentPage(ExportPageIndex(
          47)).value)).value) == Last3072Page
  var exact = ExportCommitmentLimits(exports: ElementLimit(count), nodes: ElementLimit(info.nodes),
      hashBytes: ByteLimit(info.hashBytes))
  assert prepareExportCommitment(source, exact).error == ExportCommitmentError.None
  exact.nodes = ElementLimit(info.nodes-1)
  assert prepareExportCommitment(source, exact).error == ExportCommitmentError.LimitExceeded
  if count > 0:
    exact = commitmentLimits()
    exact.exports = ElementLimit(count-1)
    assert prepareExportCommitment(source, exact).error == ExportCommitmentError.LimitExceeded
    exact = commitmentLimits()
    exact.hashBytes = ByteLimit(info.hashBytes-1)
    assert prepareExportCommitment(source, exact).error == ExportCommitmentError.LimitExceeded
let halt = @[50'u8, 0]
let exporting = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), @[10'u8, 8]]
let good = reportGuest([exporting[0], exporting[1], exporting[2], refinementImmediate(8, 0), halt], declared = 1)
let panic = reportGuest([exporting[0], exporting[1], exporting[2], @[0'u8]], declared = 1)
let mixedSource = commitmentSource([good, reportGuest([halt], declared = 1, missing = true), panic])
let selected = mixedSource.identitySource.value.authorizedDigests.value.digestReport.value
assert selected.reportItem(FetchItemIndex(0)).value.refinedInfo.value.kind == WorkKind.Success, "mixed success kind"
assert selected.reportItem(FetchItemIndex(1)).value.refinedInfo.value.kind == WorkKind.BadExports, "missing code export mismatch"
assert selected.reportItem(FetchItemIndex(2)).value.refinedInfo.value.kind == WorkKind.BadExports, "panic discards exports before I"
let mixed = prepareExportCommitment(mixedSource, commitmentLimits()).value
assert mixed.commitmentInfo.value.root.bytes == MixedRoot, "mixed root"
assert array[32, byte](blake2b256(array[4104, byte](mixed.commitmentPage(ExportPageIndex(
    0)).value)).value) == MixedPage, "mixed page"
var copy = array[4104, byte](mixed.commitmentPage(ExportPageIndex(0)).value)
copy[2] = copy[2] xor 255
var changed = mixed.commitmentInfo.value
changed.root.bytes[0] = changed.root.bytes[0] xor 255
assert mixed.commitmentInfo.value.root.bytes == MixedRoot, "mixed root"
assert array[4104, byte](mixed.commitmentPage(ExportPageIndex(0)).value) != copy
assert prepareExportCommitment(default(ReportIdentity), commitmentLimits()).error ==
    ExportCommitmentError.InvalidSource
assert default(ExportCommitment).commitmentInfo.error == ExportCommitmentError.Uninitialized
assert default(ExportCommitment).commitmentSource.error == ExportCommitmentError.Uninitialized
assert default(ExportCommitment).commitmentPage(ExportPageIndex(0)).error ==
    ExportCommitmentError.Uninitialized
proc detached(): ExportCommitment =
  ## Original source/fixture handles retire while the immutable commitment retains its full provenance graph.
  prepareExportCommitment(zeroExportSource(3), commitmentLimits()).value
assert detached().commitmentInfo.value.root.bytes == ZeroRoots[2]
proc cycle() =
  ## Release fresh complete source/tree owners and refused candidates on each ARC iteration.
  let source = zeroExportSource(3)
  let done = prepareExportCommitment(source, commitmentLimits()).value
  assert done.commitmentInfo.value.root.bytes == ZeroRoots[2]
  discard done.commitmentPage(ExportPageIndex(0)).value
  assert prepareExportCommitment(source, default(ExportCommitmentLimits)).error ==
      ExportCommitmentError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_export_commitment", 1000, before, after)
echo "PVM export commitment passed"
echo "ARC_RELEASE cycles=1000 unchanged"
