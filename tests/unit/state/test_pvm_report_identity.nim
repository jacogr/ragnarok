# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_report_identity_arc_release"}

## Source-derived hashes, exact dictionary keys, byte policies, immutable copies and owner lifetimes.

import std/[assertions, syncio]
import ../../../src/state/[report_identity, authorized_refinement, authorization_invocation,
  refinement_report, refinement_digest]
import ../../../src/codec/[bounded, composite, work_package, work_report]
import ../../../src/crypto/primitives
import ../../support/[pvm_report_identity, arc_evidence]

let a = packageImport(identityKey(1), ImportIndex(0))
let b = packageImport(identityKey(2), ImportIndex(32767))
let root = rootImport(SegmentRoot(bytes: identityKey(9).bytes), ImportIndex(1))
let original = identityFixture([@[a, root, a], @[b, a]], prerequisites = 6)
var pairs = @[identityPair(1), identityPair(2)]
let complete = prepareReportIdentity(original, pairs, identityLimits()).value
let info = complete.identityInfo.value
assert info.lookupCount == 2 and info.context.prerequisiteCount == 6
assert uint64(info.core) == 0x1234 and uint32(info.context.lookupSlot) == 20
assert uint64(info.authorizationGasUsed) == uint64(
    original.authorizedInfo.value.authorizationGasUsed)
let package = original.authorizedSource.value.authorizationPackage.value
let packageInfo = package.workPackageInfo.value
var wire = newSeq[byte](packageInfo.consumed)
assert package.encodeOwnedWorkPackage(wire).error == PackageError.None
assert info.packageHash.bytes == array[32, byte](blake2b256(wire).value)
var preimage = newSeq[byte](34)
let codeHash = array[32, byte](packageInfo.codeHash)
for index in 0..<32: preimage[index] = codeHash[index] # Authorizer hashes the declared hash, not code/envelope/authorization bytes.
preimage[32] = 81
preimage[33] = 82
assert info.authorizer.bytes == array[32, byte](blake2b256(preimage).value)
# Python hashlib BLAKE2b-256 independently hashes the literal halt envelope's metadata preimage,
# then its 32-byte code hash followed by raw [81,82]; no Nim codec/hash output generated these constants.
assert info.authorizer.bytes == [135'u8, 213, 103, 242, 20, 152, 180, 98, 176, 222, 141, 161,
  79, 29, 49, 105, 64, 222, 87, 251, 188, 180, 50, 157, 43, 204, 53, 109, 140, 219, 60, 224]
assert complete.identitySource.value.authorizedDigests.value.digestCount.value == 2
assert complete.identityRoot(identityKey(2)).value.bytes == identityPair(2).segmentRoot.bytes
assert complete.identityRoot(identityKey(9)).error == ReportIdentityError.MissingKey
assert complete.identityLookupAt(ReportLookupIndex(high(uint64))).error ==
    ReportIdentityError.InvalidIndex
assert complete.identityLookupAt(ReportLookupIndex(2)).error == ReportIdentityError.InvalidIndex
# Missing, extra, repeated and descending keys cannot masquerade as the exact canonical dictionary.
for invalid in [@[identityPair(1)], @[identityPair(1), identityPair(3)], @[identityPair(1),
    identityPair(2), identityPair(9)]]:
  assert prepareReportIdentity(original, invalid, identityLimits()).error ==
      ReportIdentityError.InvalidLookup
for invalid in [@[identityPair(1), identityPair(1)], @[identityPair(2), identityPair(1)]]:
  assert prepareReportIdentity(original, invalid, identityLimits()).error ==
      ReportIdentityError.NonCanonical
# Extra keys fail independently of the shared dependency ceiling; repeated imports require only one entry.
let roomy = identityFixture([@[a, b, a]])
assert prepareReportIdentity(roomy, [identityPair(1), identityPair(2), identityPair(3)],
    identityLimits()).error == ReportIdentityError.InvalidLookup
assert prepareReportIdentity(roomy, [], identityLimits()).error == ReportIdentityError.InvalidLookup
var alternative = @[identityPair(1), identityPair(2)]
alternative[0].segmentRoot.bytes[31] = 255
let alternate = prepareReportIdentity(original, alternative, identityLimits()).value
assert alternate.identityInfo.value.packageHash.bytes == info.packageHash.bytes
assert alternate.identityRoot(identityKey(1)).value.bytes[31] ==
    255 # Key validation deliberately does not certify root correspondence.
let noDependencies = identityFixture([@[root]], prerequisites = 8)
assert prepareReportIdentity(noDependencies, [], identityLimits()).value.identityInfo.value.lookupCount == 0
assert prepareReportIdentity(noDependencies, [identityPair(1)], identityLimits()).error ==
    ReportIdentityError.InvalidLookup
let empty = identityFixture([newSeq[ImportReference](0)], configuration = @[])
let emptyDone = prepareReportIdentity(empty, [], identityLimits()).value
assert emptyDone.identityInfo.value.authorizer.bytes != info.authorizer.bytes
assert emptyDone.identityInfo.value.authorizer.bytes == [8'u8, 249, 221, 95, 240, 152, 196, 19,
  36, 53, 117, 246, 45, 229, 204, 201, 56, 148, 23, 146, 228, 104, 2, 33, 131, 64, 148, 237,
  253, 243, 134, 32] # Empty configuration contributes exactly zero bytes after the same code hash.
assert emptyDone.identityInfo.value.packageHash.bytes != info.packageHash.bytes
# Exact inclusive byte policies authorize hashing; one byte less refuses before copying either preimage.
var cap = ReportIdentityLimits(packageBytes: ByteLimit(packageInfo.consumed),
    authorizerBytes: ByteLimit(34))
assert prepareReportIdentity(original, pairs, cap).error == ReportIdentityError.None
cap.packageBytes = ByteLimit(packageInfo.consumed-1)
assert prepareReportIdentity(original, pairs, cap).error == ReportIdentityError.LimitExceeded
cap.packageBytes = ByteLimit(packageInfo.consumed)
cap.authorizerBytes = ByteLimit(33)
assert prepareReportIdentity(original, pairs, cap).error == ReportIdentityError.LimitExceeded
cap = ReportIdentityLimits(packageBytes: ByteLimit(4096), authorizerBytes: ByteLimit(32))
assert prepareReportIdentity(empty, [], cap).error == ReportIdentityError.None
# Extraction copies and caller replacements cannot mutate retained dictionary or metadata.
pairs[0] = identityPair(7)
var copied = complete.identityLookupAt(ReportLookupIndex(0)).value
copied.segmentRoot.bytes[31] = 255
var changed = complete.identityInfo.value
changed.context.lookupSlot = LookupSlot(0)
assert complete.identityLookupAt(ReportLookupIndex(0)).value.segmentRoot.bytes == identityPair(
    1).segmentRoot.bytes
assert uint32(complete.identityInfo.value.context.lookupSlot) == 20
assert prepareReportIdentity(default(AuthorizedRefinement), [], identityLimits()).error ==
    ReportIdentityError.InvalidSource
assert default(ReportIdentity).identityInfo.error == ReportIdentityError.Uninitialized
assert default(ReportIdentity).identitySource.error == ReportIdentityError.Uninitialized
assert default(ReportIdentity).identityRoot(identityKey(1)).error ==
    ReportIdentityError.Uninitialized
assert default(ReportIdentity).identityLookupAt(ReportLookupIndex(0)).error ==
    ReportIdentityError.Uninitialized
proc detached(): ReportIdentity =
  ## Retain only the prepared owner after original source and borrowed dictionary handles retire.
  let source = identityFixture([@[a, a]])
  prepareReportIdentity(source, [identityPair(1)], identityLimits()).value
assert detached().identityRoot(identityKey(1)).value.bytes == identityPair(1).segmentRoot.bytes
proc cycle() =
  ## Fresh original execution and identity owners plus local refusals release their entire acyclic graph.
  let source = identityFixture([@[a, root], @[b, a]])
  let done = prepareReportIdentity(source, [identityPair(1), identityPair(2)], identityLimits()).value
  assert done.identityInfo.value.lookupCount == 2
  assert prepareReportIdentity(source, [identityPair(1)], identityLimits()).error ==
      ReportIdentityError.InvalidLookup
  assert prepareReportIdentity(source, [identityPair(1), identityPair(2)], default(
      ReportIdentityLimits)).error == ReportIdentityError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_report_identity", 1000, before, after)
echo "PVM report identity passed"
echo "ARC_RELEASE cycles=1000 unchanged"
