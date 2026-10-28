# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_import_justification_arc_release"}

## Independent inclusion witnesses, shape/work policy, tampering, canonical path bytes and immutable ownership.

import std/assertions
import std/syncio
import ../../../src/state/import_justification as state_import_justification
import ../../../src/state/export_commitment as state_export_commitment
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/natural as codec_natural
import ../../../src/codec/work_package as codec_work_package
import ../../../src/codec/work_report as codec_work_report
import ../../../src/pvm/host_fetch as pvm_host_fetch
import ../../support/pvm_import_justification
import ../../support/pvm_import_vectors
import ../../support/pvm_export_commitment
import ../../support/testing_arc_evidence

proc expectFailure(outcome: ImportJustificationResult[VerifiedImport],
    reason: ImportJustificationError) =
  ## Compare the exact selected reason without reading any failed success payload.
  assert outcome.error == reason

let root = SegmentRoot(bytes: ThreeRoot)
let paths = @[importPath(ThreePath0), importPath(ThreePath1), importPath(ThreePath2)]
# Every ordinal and both sibling directions must reconstruct the same independently computed three-leaf root.
for index in 0..<3:
  let segment = importSegment(byte(index+1))
  let done = verifyImportSegment(root, ImportIndex(uint16(index)), segment, paths[index],
      importLimits()).value
  let info = done.verifiedImportInfo.value
  assert info.root.bytes == ThreeRoot and uint16(info.index) == uint16(index)
  assert info.siblings == 2 and info.payloadBytes == 4168 and info.hashBytes == 4244
  assert array[4104, byte](done.verifiedImportSegment.value) == array[4104, byte](segment)
  let proof = done.verifiedImportProof.value
  assert proof.len == 65 and proof[0] == 2
  assert uint64(decode(proof).value) == 2
  for sibling in 0..<2:
    for octet in 0..<32: assert proof[1+sibling*32+octet] == paths[index][sibling].bytes[octet]
  var exact = ImportJustificationLimits(siblings: ElementLimit(2), payloadBytes: ByteLimit(4168),
      hashBytes: ByteLimit(4244))
  expectFailure(verifyImportSegment(root, ImportIndex(uint16(index)), segment, paths[index],
      exact), ImportJustificationError.None)
  exact.siblings = ElementLimit(1)
  expectFailure(verifyImportSegment(root, ImportIndex(uint16(index)), segment, paths[index],
      exact), ImportJustificationError.LimitExceeded)
  exact = importLimits()
  exact.payloadBytes = ByteLimit(4167)
  expectFailure(verifyImportSegment(root, ImportIndex(uint16(index)), segment, paths[index],
      exact), ImportJustificationError.LimitExceeded)
  exact = importLimits()
  exact.hashBytes = ByteLimit(4243)
  expectFailure(verifyImportSegment(root, ImportIndex(uint16(index)), segment, paths[index],
      exact), ImportJustificationError.LimitExceeded)
  var altered = array[4104, byte](segment)
  for position in [0, 1, 4103]:
    altered[position] = altered[position] xor 1
    expectFailure(verifyImportSegment(root, ImportIndex(uint16(index)), FetchSegment(altered),
        paths[index], importLimits()), ImportJustificationError.RootMismatch)
    altered[position] = altered[position] xor 1
  expectFailure(verifyImportSegment(root, ImportIndex(uint16((index+1) mod 3)), segment, paths[
      index], importLimits()), ImportJustificationError.RootMismatch)
# Tamper each sibling octet; reversing or truncating the path cannot preserve the original witness.
for sibling in 0..<2:
  for octet in 0..<32:
    var altered = importPath(ThreePath0)
    altered[sibling].bytes[octet] = altered[sibling].bytes[octet] xor 1
    expectFailure(verifyImportSegment(root, ImportIndex(0), importSegment(1), altered, importLimits(
      )), ImportJustificationError.RootMismatch)
let reversed = @[paths[0][1], paths[0][0]]
expectFailure(verifyImportSegment(root, ImportIndex(0), importSegment(1), reversed, importLimits(
  )), ImportJustificationError.RootMismatch)
expectFailure(verifyImportSegment(root, ImportIndex(0), importSegment(1), [paths[0][0]],
    importLimits(
  )), ImportJustificationError.RootMismatch)
let extended = @[SegmentRoot(), paths[0][0], paths[0][1]]
expectFailure(verifyImportSegment(root, ImportIndex(0), importSegment(1), extended, importLimits(
  )), ImportJustificationError.RootMismatch)
var otherRoot = root
otherRoot.bytes[31] = otherRoot.bytes[31] xor 1
expectFailure(verifyImportSegment(otherRoot, ImportIndex(0), importSegment(1), paths[0],
    importLimits(
  )), ImportJustificationError.RootMismatch)
# A padded slot is the raw zero hash, so supplying a real zero segment at its ordinal must fail.
expectFailure(verifyImportSegment(root, ImportIndex(3), importSegment(), importPath(PaddingPath),
    importLimits()), ImportJustificationError.RootMismatch)
var paddingSibling = importPath(ThreePath2)
paddingSibling[1].bytes[0] = 1
expectFailure(verifyImportSegment(root, ImportIndex(2), importSegment(3), paddingSibling,
    importLimits(
  )), ImportJustificationError.RootMismatch)
# Singleton and maximal actual export ordinals interoperate with independently emitted report export commitments.
let singleton = SegmentRoot(bytes: SingletonRoot)
let single = verifyImportSegment(singleton, ImportIndex(0), importSegment(), [], importLimits()).value
assert single.verifiedImportProof.value == @[0'u8]
let singletonLimits = ImportJustificationLimits(siblings: ElementLimit(0), payloadBytes: ByteLimit(
    4104), hashBytes: ByteLimit(4108))
expectFailure(verifyImportSegment(singleton, ImportIndex(0), importSegment(), [], singletonLimits),
    ImportJustificationError.None)
let partial = verifyImportSegment(SegmentRoot(bytes: PartialRoot), ImportIndex(64), importSegment(),
    importPath(PartialPath), importLimits()).value
assert partial.verifiedImportInfo.value.siblings == 7
let maximum = verifyImportSegment(SegmentRoot(bytes: MaximumRoot), ImportIndex(3071), importSegment(
  ), importPath(MaximumPath), importLimits()).value
assert maximum.verifiedImportProof.value.len == 385
let exports = prepareExportCommitment(zeroExportSource(3072), commitmentLimits()).value
assert exports.commitmentInfo.value.root.bytes == MaximumRoot
expectFailure(verifyImportSegment(exports.commitmentInfo.value.root, ImportIndex(3071),
    importSegment(), importPath(MaximumPath), importLimits()), ImportJustificationError.None)
expectFailure(verifyImportSegment(SegmentRoot(), ImportIndex(0), importSegment(), [], importLimits(
  )), ImportJustificationError.RootMismatch)
# Shape errors precede local policies, shifts and hashing; public uint16 values are never masked into valid import ordinals.
for index in [3072'u16, 32767, 32768, high(uint16)]:
  expectFailure(verifyImportSegment(root, ImportIndex(index), importSegment(), paths[0], default(
      ImportJustificationLimits)), ImportJustificationError.InvalidIndex)
expectFailure(verifyImportSegment(singleton, ImportIndex(1), importSegment(), [], default(
    ImportJustificationLimits)), ImportJustificationError.InvalidIndex)
expectFailure(verifyImportSegment(root, ImportIndex(0), importSegment(), newSeq[SegmentRoot](13),
    default(ImportJustificationLimits)), ImportJustificationError.InvalidProof)
# Caller sequence, copied segment/path/encoded bytes and copied metadata cannot mutate retained verified storage.
var borrowed = importPath(ThreePath0)
let retained = verifyImportSegment(root, ImportIndex(0), importSegment(1), borrowed, importLimits()).value
borrowed[0].bytes[0] = borrowed[0].bytes[0] xor 1
var copiedPath = retained.verifiedImportPath.value
copiedPath[0].bytes[0] = copiedPath[0].bytes[0] xor 1
var copiedBytes = retained.verifiedImportProof.value
copiedBytes[0] = 255
var copiedSegment = array[4104, byte](retained.verifiedImportSegment.value)
copiedSegment[0] = 255
var copiedInfo = retained.verifiedImportInfo.value
copiedInfo.root.bytes[0] = copiedInfo.root.bytes[0] xor 1
assert retained.verifiedImportPath.value[0].bytes == ThreePath0[0]
assert retained.verifiedImportProof.value[0] == 2
assert array[4104, byte](retained.verifiedImportSegment.value)[0] == 1
assert retained.verifiedImportInfo.value.root.bytes == ThreeRoot
assert default(VerifiedImport).verifiedImportInfo.error == ImportJustificationError.Uninitialized
assert default(VerifiedImport).verifiedImportSegment.error == ImportJustificationError.Uninitialized
assert default(VerifiedImport).verifiedImportPath.error == ImportJustificationError.Uninitialized
assert default(VerifiedImport).verifiedImportProof.error == ImportJustificationError.Uninitialized
proc detached(): VerifiedImport =
  ## Retire original temporary sibling/segment arguments while preserving verified owned extraction.
  verifyImportSegment(root, ImportIndex(2), importSegment(3), importPath(ThreePath2), importLimits()).value
assert uint16(detached().verifiedImportInfo.value.index) == 2
proc cycle() =
  ## Release fresh verified witnesses, proof copies and cryptographically refused candidates on every iteration.
  let done = detached()
  assert done.verifiedImportProof.value.len == 65
  expectFailure(verifyImportSegment(SegmentRoot(), ImportIndex(0), importSegment(1), importPath(
      ThreePath0), importLimits()), ImportJustificationError.RootMismatch)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_import_justification", 1000, before, after)
echo "PVM import justification passed"
echo "ARC_RELEASE cycles=1000 unchanged"
