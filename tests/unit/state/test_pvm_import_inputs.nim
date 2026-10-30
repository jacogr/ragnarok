# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_import_inputs_arc_release"}

## Bind every ordered package import to real verified leaf owners, with exact dictionaries and bounded ownership.

import std/[assertions, syncio]
import "../../../src/state/import/inputs" as import_inputs
import "../../../src/state/import/justification" as import_justification
import ../../../src/state/extrinsic_inputs
import ../../../src/codec/bounded
import ../../../src/codec/work/[package as work_package, report as work_report]
import ../../../src/pvm/host/fetch as host_fetch
import ../../support/[pvm_import_inputs, pvm_import_justification, pvm_import_vectors, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Select a refusal to prove that binding immutable proofs does no additional hashing.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe exact hash call counts after all genuine input preparation finishes.
proc expect[T](outcome: ImportInputsResult[T], reason: ImportInputsError) =
  ## Check exact reasons without extracting failed alternatives.
  assert outcome.error == reason, "import binding reason mismatch"
proc input(inputs: VerifiedImportInputs, item, index: uint64): ImportInputsResult[VerifiedImport] =
  ## Keep full-width ordinal fixtures concise while preserving public nominal domains.
  inputs.importInput(FetchItemIndex(item), ImportInputIndex(index))

let p0 = inputProof(0)
let p1 = inputProof(1)
let p2 = inputProof(2)
let direct = rootImport(SegmentRoot(bytes: ThreeRoot), ImportIndex(0))
let first = packageImport(inputKey(1), ImportIndex(1))
let second = packageImport(inputKey(2), ImportIndex(2))
let manifests = @[@[direct, first, direct], newSeq[ImportReference](0), @[second, first]]
let source = inputSource(manifests, 6)
var rows = @[@[p0, p1, p0], newSeq[VerifiedImport](0), @[p2, p1]]
var lookup = @[inputPair(1), inputPair(2)]
let bound = bindImportInputs(source, rows, lookup, inputLimits()).value
let info = bound.importInputsInfo.value
assert info.items == 3 and info.entries == 5 and info.lookupCount == 2
assert info.witnessBytes == 20840
assert uint16(bound.input(0, 1).value.verifiedImportInfo.value.index) == 1
assert uint16(bound.input(2, 0).value.verifiedImportInfo.value.index) == 2
assert bound.input(0, 0).value.verifiedImportProof.value == p0.verifiedImportProof.value
let original = bound.importInputsExtrinsics.value.extrinsicInputsPackage.value
assert original.workPackageInfo.value.context.prerequisiteCount == 6
assert original.workItemAt(2).value.importAt(0).value.package.bytes == inputKey(2).bytes
let extrinsic = bound.importInputsExtrinsics.value.extrinsicInput(FetchItemIndex(1),
    ExtrinsicInputIndex(0)).value
assert extrinsic == @[97'u8, 98, 99]
# Repeated handles count for every manifest occurrence; both local caps accept exact totals and reject one below.
var exact = ImportInputsLimits(entries: ElementLimit(5), witnessBytes: ByteLimit(20840))
expect(bindImportInputs(source, rows, lookup, exact), ImportInputsError.None)
exact.entries = ElementLimit(4)
expect(bindImportInputs(source, rows, lookup, exact), ImportInputsError.LimitExceeded)
exact.entries = ElementLimit(5)
exact.witnessBytes = ByteLimit(20839)
expect(bindImportInputs(source, rows, lookup, exact), ImportInputsError.LimitExceeded)
# Reject complete-table shape errors, never return an authenticated prefix or silently omit empty item rows.
expect(bindImportInputs(source, [], lookup, inputLimits()), ImportInputsError.InvalidShape)
let absent = @[@[p0, p1], newSeq[VerifiedImport](0), @[p2, p1]]
expect(bindImportInputs(source, absent, lookup, inputLimits()), ImportInputsError.InvalidShape)
let extra = @[@[p0, p1, p0], newSeq[VerifiedImport](0), @[p2, p1, p1]]
expect(bindImportInputs(source, extra, lookup, inputLimits()), ImportInputsError.InvalidShape)
let reordered = @[@[p0, p1, p0], @[p2, p1], newSeq[VerifiedImport](0)]
expect(bindImportInputs(source, reordered, lookup, inputLimits()), ImportInputsError.InvalidShape)
let swapped = @[@[p1, p0, p0], newSeq[VerifiedImport](0), @[p2, p1]]
expect(bindImportInputs(source, swapped, lookup, inputLimits()), ImportInputsError.IndexMismatch)
let missingProof = @[@[p0, p1, p0], newSeq[VerifiedImport](0), @[p2, default(VerifiedImport)]]
expect(bindImportInputs(source, missingProof, lookup, inputLimits()),
    ImportInputsError.InvalidImport)
let singleton = verifyImportSegment(SegmentRoot(bytes: SingletonRoot), ImportIndex(0),
    importSegment(), [], importLimits()).value
let wrongRoot = @[@[p0, p1, singleton], newSeq[VerifiedImport](0), @[p2, p1]]
expect(bindImportInputs(source, wrongRoot, lookup, inputLimits()), ImportInputsError.RootMismatch)
# Every package key is required exactly once, including imports in a different item; direct roots use no key.
expect(bindImportInputs(source, rows, [inputPair(1)], inputLimits()),
    ImportInputsError.InvalidLookup)
expect(bindImportInputs(source, rows, [inputPair(1), inputPair(3)], inputLimits()),
    ImportInputsError.InvalidLookup)
expect(bindImportInputs(source, rows, [inputPair(2), inputPair(1)], inputLimits()),
    ImportInputsError.NonCanonical)
expect(bindImportInputs(source, rows, [inputPair(1), inputPair(1)], inputLimits()),
    ImportInputsError.NonCanonical)
expect(bindImportInputs(source, rows, [inputPair(1), inputPair(2), inputPair(3)], inputLimits()),
    ImportInputsError.InvalidLookup)
let roomy = inputSource(manifests)
expect(bindImportInputs(roomy, rows, [inputPair(1), inputPair(2), inputPair(3)], inputLimits()),
    ImportInputsError.InvalidLookup)
let directOnly = inputSource([@[direct]])
expect(bindImportInputs(directOnly, [@[p0]], [inputPair(1)], inputLimits()),
    ImportInputsError.InvalidLookup)
expect(bindImportInputs(directOnly, [@[p0]], [], inputLimits()), ImportInputsError.None)
var changedRoot = inputPair(2)
changedRoot.segmentRoot.bytes[31] = changedRoot.segmentRoot.bytes[31] xor 1
expect(bindImportInputs(source, rows, [inputPair(1), changedRoot], inputLimits()),
    ImportInputsError.RootMismatch)
# A different explicitly supplied correspondence plus a valid matching proof is accepted without asserting root freshness.
let packageOnly = inputSource([@[packageImport(inputKey(1), ImportIndex(0))]])
let alternative = SegmentLookup(packageHash: inputKey(1), segmentRoot: SegmentRoot(
    bytes: SingletonRoot))
let alternate = bindImportInputs(packageOnly, [@[singleton]], [alternative], inputLimits()).value
assert alternate.input(0, 0).value.verifiedImportInfo.value.root.bytes == SingletonRoot
expect(bindImportInputs(packageOnly, [@[p0]], [inputPair(1)], inputLimits()),
    ImportInputsError.None)
# Empty import rows need no dictionary/witness budget, while real extrinsics remain bound to the original package.
let empty = inputSource([newSeq[ImportReference](0)], 8)
let emptyRows = [newSeq[VerifiedImport](0)]
let emptyBound = bindImportInputs(empty, emptyRows, [], default(ImportInputsLimits)).value
assert emptyBound.importInputsInfo.value.entries == 0
assert emptyBound.importInputsExtrinsics.value.extrinsicInputsInfo.value.entries == 1
expect(bindImportInputs(empty, emptyRows, [inputPair(1)], inputLimits()),
    ImportInputsError.InvalidLookup)
# The full eight-key ceiling works with one repeated leaf proof shared by all package dependencies.
var eightReferences: seq[ImportReference] = @[]
var eightLookup: seq[SegmentLookup] = @[]
var eightProofs: seq[VerifiedImport] = @[]
for index in 1..8:
  eightReferences.add(packageImport(inputKey(byte(index)), ImportIndex(0)))
  eightLookup.add(inputPair(byte(index)))
  eightProofs.add(p0)
let eight = bindImportInputs(inputSource([eightReferences]), [eightProofs], eightLookup,
    inputLimits()).value
assert eight.importInputsInfo.value.lookupCount == 8
expect(bindImportInputs(inputSource([@[first]], 7), [@[p1]], eightLookup, inputLimits(
  )), ImportInputsError.InvalidLookup)
# Maximum protocol occurrence and item counts retain bounded descriptors without copying leaf payloads.
let maximumProof = verifyImportSegment(SegmentRoot(bytes: MaximumRoot), ImportIndex(3071),
  importSegment(), importPath(MaximumPath), importLimits()).value
let maximumReference = rootImport(SegmentRoot(bytes: MaximumRoot), ImportIndex(3071))
var maximumReferences = newSeq[ImportReference](3072)
var maximumProofs = newSeq[VerifiedImport](3072)
for index in 0..<3072:
  maximumReferences[index] = maximumReference
  maximumProofs[index] = maximumProof
let maximum = bindImportInputs(inputSource([maximumReferences]), [maximumProofs], [], inputLimits()).value
assert maximum.importInputsInfo.value.entries == 3072
assert maximum.importInputsInfo.value.witnessBytes == 13787136
let sixteenSource = inputSource(newSeq[seq[ImportReference]](16))
let sixteen = bindImportInputs(sixteenSource, newSeq[seq[VerifiedImport]](16), [], default(
    ImportInputsLimits)).value
assert sixteen.importInputsInfo.value.items == 16
# Full-width access checks precede narrowing, including an existing empty row and all default owner getters.
for item in [3'u64, high(uint64)]: expect(bound.input(item, 0), ImportInputsError.InvalidIndex)
for index in [3'u64, high(uint64)]: expect(bound.input(0, index), ImportInputsError.InvalidIndex)
expect(bound.input(1, 0), ImportInputsError.InvalidIndex)
expect(default(VerifiedImportInputs).importInputsInfo, ImportInputsError.Uninitialized)
expect(default(VerifiedImportInputs).importInputsExtrinsics, ImportInputsError.Uninitialized)
expect(default(VerifiedImportInputs).importInputsLookup, ImportInputsError.Uninitialized)
expect(default(VerifiedImportInputs).input(0, 0), ImportInputsError.Uninitialized)
expect(bindImportInputs(default(VerifiedExtrinsics), rows, lookup, inputLimits()),
    ImportInputsError.InvalidSource)
# Refuse the backend after genuine preparation: matching immutable proof handles needs zero cryptographic calls.
reset(1)
expect(bindImportInputs(source, rows, lookup, inputLimits()), ImportInputsError.None)
expect(bindImportInputs(source, missingProof, lookup, inputLimits()),
    ImportInputsError.InvalidImport)
expect(bindImportInputs(source, rows, lookup, exact), ImportInputsError.LimitExceeded)
assert hashes() == 0
reset(0)
# Retained row descriptors, fixed dictionary copies, output proof bytes and metadata survive caller mutation independently.
rows[0][0] = singleton
rows[2] = @[]
lookup[0].segmentRoot.bytes[0] = 255
var copiedLookup = bound.importInputsLookup.value
copiedLookup[0].packageHash.bytes[0] = 255
var copiedProof = bound.input(0, 0).value.verifiedImportProof.value
copiedProof[0] = 255
var copiedInfo = bound.importInputsInfo.value
copiedInfo.entries = 0
assert bound.input(0, 0).value.verifiedImportInfo.value.root.bytes == ThreeRoot
assert bound.input(2, 0).value.verifiedImportInfo.value.root.bytes == ThreeRoot
assert bound.importInputsLookup.value[0].packageHash.bytes == inputKey(1).bytes
assert bound.importInputsLookup.value[0].segmentRoot.bytes == ThreeRoot
assert bound.input(0, 0).value.verifiedImportProof.value[0] == 2
assert bound.importInputsInfo.value.entries == 5
proc detached(): VerifiedImportInputs =
  ## Retire all package, row and proof temporaries while retaining both original input kinds.
  bindImportInputs(inputSource([@[rootImport(SegmentRoot(bytes: ThreeRoot), ImportIndex(0))]]),
    [@[inputProof(0)]], [], inputLimits()).value
assert detached().input(0, 0).value.verifiedImportInfo.value.root.bytes == ThreeRoot
proc cycle() =
  ## Release successful retained owners, copied dictionary/proof bytes and refused candidates on each iteration.
  let done = detached()
  assert done.importInputsLookup.value.len == 0
  assert done.input(0, 0).value.verifiedImportProof.value.len == 65
  expect(bindImportInputs(source, missingProof, [inputPair(1), inputPair(2)], inputLimits()),
      ImportInputsError.InvalidImport)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "import input ARC release"
recordArcRelease("pvm_import_inputs", 1000, before, after)
echo "PVM import inputs passed"
echo "ARC_RELEASE cycles=1000 unchanged"
