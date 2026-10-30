# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_work_digests_arc_release"}

## Original source-bound report guests verify C's field derivation, literal hash/wire witnesses and ownership.

import std/[assertions, syncio]
import ../../../src/state/refinement/[digest as refinement_digest, report as refinement_report]
import ../../../src/pvm/host/fetch as host_fetch
import ../../../src/codec/[bounded, composite]
import ../../../src/codec/work/[package as work_package, digest as work_digest]
import ../../support/[pvm_work_digests, pvm_report_results, pvm_refinement_outcome, arc_evidence]

const payloadHash = [186'u8, 170, 40, 136, 247, 203, 180, 131, 40, 171, 152, 2, 14, 173, 35, 122,
    12, 184, 229, 214, 17, 9, 91, 199, 184, 18, 183, 125, 142, 159, 116, 234]
const emptyHash = [14'u8, 87, 81, 192, 38, 229, 67, 178, 232, 171, 46, 176, 96, 153, 218, 161, 209,
    229, 223, 71, 119, 143, 119, 135, 250, 171, 69, 205, 241, 47, 227, 168]
# Literal hashes were generated independently with Python hashlib.blake2b(digest_size=32).
let halt = @[50'u8, 0]
let returning = @[refinementImmediate(7, 196608), refinementImmediate(8, 3), halt]
let empty = @[refinementImmediate(8, 0), halt]
let payloads = @[@[0'u8, 255, 128, 1], newSeq[byte]()]
let fixture = digestFixture([reportGuest(returning), reportGuest(empty)], payloads,
    manifests = true)
let report = digestReportFixture(fixture, [])
let digests = prepareRefinementDigests(report, digestLimits()).value
assert digests.digestCount.value == 2
proc check(digests: RefinementDigests, index: uint64, kind: WorkKind): RefinedDigest =
  ## Compare source-derived fields and borrowed-codec decoding against the genuine final item and original manifest.
  let digest = digests.digestAt(FetchItemIndex(index)).value
  let info = digest.digestInfo.value
  let item = digest.digestSource.value
  let declaration = item.refinedSource.value.workItemInfo.value
  let normalized = item.refinedInfo.value
  assert info.kind == kind and uint64(info.item) == index
  assert uint32(info.service) == uint32(declaration.service)
  assert array[32, byte](info.codeHash) == array[32, byte](declaration.codeHash)
  assert uint64(info.accumulateGas) == uint64(65536+index)
  assert uint64(info.refine.gasUsed) == uint64(normalized.gasUsed)
  assert uint64(info.refine.exports) == uint64(declaration.exports)
  assert uint64(info.refine.imports) == uint64(declaration.imports)
  assert uint64(info.refine.extrinsicCount) == uint64(declaration.extrinsics)
  let bytes = digest.digestBytes.value
  assert uint64(bytes.len) == info.encodedBytes
  let decoded = decodeDigestBorrowed(bytes, ByteLimit(49152))
  assert decoded.error == CompositeError.None and decoded.consumed == bytes.len
  let value = decoded.value
  assert value.output.kind == kind and uint32(value.service) == uint32(info.service)
  assert array[32, byte](value.codeHash) == array[32, byte](info.codeHash)
  assert array[32, byte](value.payloadHash) == array[32, byte](info.payloadHash)
  assert uint64(value.accumulateGas) == uint64(info.accumulateGas)
  assert uint64(value.refine.gasUsed) == uint64(info.refine.gasUsed)
  assert uint64(value.refine.imports) == uint64(info.refine.imports)
  assert uint64(value.refine.exports) == uint64(info.refine.exports)
  assert uint64(value.refine.extrinsicCount) == uint64(info.refine.extrinsicCount)
  assert uint64(value.refine.extrinsicSize) == uint64(info.refine.extrinsicSize)
  if kind == WorkKind.Success:
    let blob = value.output.blob
    let expected = item.refinedOutput.value
    assert blob.length == expected.len and info.outputBytes == uint64(expected.len)
    for offset in 0..<blob.length: assert bytes[blob.offset+offset] == expected[offset]
    assert digest.digestOutput.value == expected
  else:
    assert digest.digestOutput.error == RefinementDigestError.NotSuccess and info.outputBytes == 0
  digest
let first = check(digests, 0, WorkKind.Success)
let second = check(digests, 1, WorkKind.Success)
assert array[32, byte](first.digestInfo.value.payloadHash) == payloadHash
assert array[32, byte](second.digestInfo.value.payloadHash) == emptyHash
assert uint64(first.digestInfo.value.refine.imports) == 2
assert uint64(first.digestInfo.value.refine.extrinsicCount) == 3
assert uint64(first.digestInfo.value.refine.extrinsicSize) == 257
assert uint64(second.digestInfo.value.refine.extrinsicSize) == 0
assert first.digestOutput.value == @[21'u8, 22, 23] and second.digestOutput.value.len == 0
assert digests.digestEncodedBytes.value == first.digestInfo.value.encodedBytes+second.digestInfo.value.encodedBytes
assert digests.digestReport.value.reportInfo.value.blobBytes == report.reportInfo.value.blobBytes
# BAD needs no preimages, yet C sums all original E4 extrinsic lengths without narrowing to sixteen bits.
let wideFixture = digestFixture([reportGuest(returning, missing = true)], [payloads[0]],
    manifests = true, wide = true)
let wide = prepareRefinementDigests(digestReportFixture(wideFixture, []), digestLimits()).value
let bad = check(wide, 0, WorkKind.Bad)
assert uint64(bad.digestInfo.value.refine.extrinsicSize) == 131073
var expected = @[42'u8, 0, 0, 0]
for octet in array[32, byte](wideFixture.package.workItemAt(
    0).value.workItemInfo.value.codeHash): expected.add(octet)
for octet in payloadHash: expected.add(octet)
# E8 accumulation allowance 65536, BAD tag, then natural metrics: used=0, imports=2, extrinsics=2, bytes=131073, exports=0.
for octet in [0'u8, 0, 1, 0, 0, 0, 0, 0, 5, 0, 2, 2, 194, 1, 0, 0]: expected.add(octet)
assert bad.digestBytes.value == expected and expected.len == 84
# Preserve all remaining final work errors, including I replacements rather than raw successful invocation results.
for variant in 0..<5:
  let guest = if variant == 0: reportGuest(returning, oversized = true)
    elif variant == 1: reportGuest([@[0'u8]])
    elif variant == 2: reportGuest(returning, credit = 0)
    elif variant == 3: reportGuest(returning, 2) else: reportGuest(returning)
  let kind = if variant == 0: WorkKind.Big elif variant == 1: WorkKind.Panic
    elif variant == 2: WorkKind.OutOfGas elif variant ==
        3: WorkKind.BadExports else: WorkKind.Oversize
  let trace = if variant == 4: newSeq[byte](49150) else: newSeq[byte]()
  let source = digestReportFixture(digestFixture([guest], [payloads[0]]), trace)
  let selected = check(prepareRefinementDigests(source, digestLimits()).value, 0, kind)
  assert array[32, byte](selected.digestInfo.value.payloadHash) == payloadHash
  assert uint64(selected.digestInfo.value.refine.exports) == (if variant == 3: 2'u64 else: 0'u64)
# Exact independent policies accept; one short refuses the entire projection with no partial owner.
for policy in 0..<5:
  var cap = digestLimits()
  case policy
  of 0: cap.items = ElementLimit(2)
  of 1: cap.payload = ByteLimit(4)
  of 2: cap.totalPayload = ByteLimit(4)
  of 3: cap.encoding = ByteLimit(first.digestInfo.value.encodedBytes)
  else: cap.totalEncoding = ByteLimit(digests.digestEncodedBytes.value)
  assert prepareRefinementDigests(report, cap).error == RefinementDigestError.None
  case policy
  of 0: cap.items = ElementLimit(1)
  of 1: cap.payload = ByteLimit(3)
  of 2: cap.totalPayload = ByteLimit(3)
  of 3: cap.encoding = ByteLimit(first.digestInfo.value.encodedBytes-1)
  else: cap.totalEncoding = ByteLimit(digests.digestEncodedBytes.value-1)
  assert prepareRefinementDigests(report, cap).error == RefinementDigestError.LimitExceeded
let lateReport = digestReportFixture(digestFixture([reportGuest(empty), reportGuest(empty)], [
    newSeq[byte](), payloads[0]]), [])
var cap = digestLimits()
cap.totalPayload = ByteLimit(3)
assert prepareRefinementDigests(lateReport, cap).error == RefinementDigestError.LimitExceeded
assert prepareRefinementDigests(default(RefinedPackage), digestLimits()).error ==
    RefinementDigestError.InvalidReport
assert digests.digestAt(FetchItemIndex(2)).error == RefinementDigestError.InvalidIndex
assert digests.digestAt(FetchItemIndex(high(uint64))).error == RefinementDigestError.InvalidIndex
assert default(RefinementDigests).digestCount.error == RefinementDigestError.Uninitialized
assert default(RefinementDigests).digestEncodedBytes.error == RefinementDigestError.Uninitialized
assert default(RefinementDigests).digestReport.error == RefinementDigestError.Uninitialized
assert default(RefinementDigests).digestAt(FetchItemIndex(0)).error ==
    RefinementDigestError.Uninitialized
assert default(RefinedDigest).digestInfo.error == RefinementDigestError.Uninitialized
assert default(RefinedDigest).digestSource.error == RefinementDigestError.Uninitialized
assert default(RefinedDigest).digestBytes.error == RefinementDigestError.Uninitialized
assert default(RefinedDigest).digestOutput.error == RefinementDigestError.Uninitialized
# Mutating extracted values cannot alter retained commitments, original final output, wire bytes or replay.
var changedWire = first.digestBytes.value
changedWire[0] = 255
var changedOutput = first.digestOutput.value
changedOutput[0] = 255
var changedInfo = first.digestInfo.value
changedInfo.payloadHash = PayloadHash(default(array[32, byte]))
assert first.digestBytes.value[0] == 42 and first.digestOutput.value[0] == 21
assert array[32, byte](first.digestInfo.value.payloadHash) == payloadHash
assert prepareRefinementDigests(report, digestLimits()).value.digestAt(FetchItemIndex(
    0)).value.digestBytes.value == first.digestBytes.value
proc detached(): RefinedDigest =
  ## An extracted digest keeps original item/source and output alive after all caller/report/collection handles retire.
  let report = digestReportFixture(digestFixture([reportGuest(returning)], [payloads[0]]), [])
  prepareRefinementDigests(report, digestLimits()).value.digestAt(FetchItemIndex(0)).value
assert detached().digestOutput.value == @[21'u8, 22, 23]
proc cycle() =
  ## Release fresh complete state/package/report, hashing scratch and both successful and rejected projections each cycle.
  let source = digestReportFixture(digestFixture([reportGuest(returning), reportGuest(empty, 1)],
      payloads), [])
  let completed = prepareRefinementDigests(source, digestLimits()).value
  discard check(completed, 0, WorkKind.Success)
  discard check(completed, 1, WorkKind.BadExports)
  var limited = digestLimits()
  limited.totalEncoding = ByteLimit(1)
  assert prepareRefinementDigests(source, limited).error == RefinementDigestError.LimitExceeded
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("pvm_work_digests", 1000, before, after)
echo "PVM work digests passed"
echo "ARC_RELEASE cycles=1000 unchanged"
