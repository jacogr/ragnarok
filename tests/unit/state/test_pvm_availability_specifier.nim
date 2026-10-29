# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_availability_specifier_arc_release"}

## Independent complete availability fields, raw-leaf trees, hash preflight and immutable original provenance.

import std/[assertions, syncio]
import ../../../src/state/availability/specifier as availability_specifier
import "../../../src/state/export/erasure" as export_erasure
import ../../../src/state/bundle_erasure
import ../../../src/state/erasure/[words as erasure_words, layout as erasure_layout]
import ../../../src/state/auditable_bundle
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
import ../../../src/crypto/primitives
import ../../support/[pvm_export_erasure, pvm_availability_vectors, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset actual hash attempts and optionally refuse the backend after original source preparation.
proc afterCalls(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Fail after a precise successful prefix, including during the final outer tree.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe exact production calls rather than trusting descriptive work metadata alone.
proc generous(): AvailabilityCommitmentLimits =
  ## Explicit local policies admit selected complete source-bound witnesses.
  AvailabilityCommitmentLimits(bytes: ByteLimit(1000000), hashBytes: ByteLimit(10000000),
      hashes: ElementLimit(100000))
proc expect[T](outcome: AvailabilityCommitmentResult[T], reason: AvailabilityCommitmentError) =
  ## Check exact alternatives without extracting a refused root or validator prefix.
  assert outcome.error == reason, "availability commitment reason"
proc source(kind: int, validators = 1023'u16): ExportErasure =
  ## Build genuine executed bundle and export erasure ownership before availability assembly.
  prepareExportErasure(exportBundle(kind, validators), exportErasureLimits()).value
proc wire(specifier: AvailabilitySpecifier): array[104, byte] =
  ## Test-only explicit GP tuple encoding compares every nominal field with the independent literal reference.
  result = default(array[104, byte])
  for index in 0..<32:
    result[index] = specifier.packageHash.bytes[index]
    result[36+index] = specifier.erasureRoot.bytes[index]
    result[70+index] = specifier.segmentRoot.bytes[index]
  for index in 0..<4: result[32+index] = byte((uint32(specifier.bundleLength) shr (index*8)) and 255)
  for index in 0..<2:
    result[68+index] = byte((uint16(specifier.erasureShards) shr (index*8)) and 255)
    result[102+index] = byte((uint16(specifier.segmentCount) shr (index*8)) and 255)
proc pair(info: AvailabilityShardInfo): array[64, byte] =
  ## Serialize copied fixed validator hash pairs without invoking any production Merkle helper.
  result = default(array[64, byte])
  for index in 0..<32:
    result[index] = array[32, byte](info.bundleHash)[index]
    result[32+index] = array[32, byte](info.exportRoot)[index]
proc verify(original: ExportErasure, expectedBundle: openArray[byte], expectedWire: array[104,
    byte], first, last: array[64, byte], calls, hashBytes: uint64): AvailabilityCommitment =
  ## Compare independent source bytes, every final specifier field and first/last validator commitments.
  let bundle = original.exportErasureSource.value.bundleErasureSource.value.layoutSource.value
  assert bundle.bundleBytes.value == @expectedBundle, "independent literal original package/bundle bytes"
  reset(0)
  let done = prepareAvailabilityCommitment(original, generous()).value
  let info = done.availabilityInfo.value
  assert uint64(hashes()) == calls, "exact independent observed hash count"
  assert info.hashes == calls, "complete call policy"
  assert info.hashBytes == hashBytes, "independent actual-preimage byte policy"
  assert wire(info.specifier) == expectedWire, "all six independent availability fields"
  assert pair(done.availabilityShard(ErasureShardIndex(0)).value) == first, "independent first validator hashes"
  let validators = uint64(uint16(info.specifier.erasureShards))
  assert pair(done.availabilityShard(ErasureShardIndex(validators-1)).value) == last, "independent last validator hashes"
  assert info.retainedBytes == validators*64, "complete retained validator-pair payload"
  assert uint16(info.specifier.segmentCount) == uint16(original.exportErasureInfo.value.exports), "proof pages do not inflate export count"
  assert done.availabilitySource.value.exportErasureInfo.value.packageHash.bytes ==
      info.specifier.packageHash.bytes, "exact original source identity"
  var cap = AvailabilityCommitmentLimits(bytes: ByteLimit(info.retainedBytes+info.workspaceBytes),
      hashBytes: ByteLimit(info.hashBytes), hashes: ElementLimit(info.hashes))
  expect(prepareAvailabilityCommitment(original, cap), AvailabilityCommitmentError.None)
  cap.bytes = ByteLimit(uint64(cap.bytes)-1)
  expect(prepareAvailabilityCommitment(original, cap), AvailabilityCommitmentError.LimitExceeded)
  cap.bytes = ByteLimit(uint64(cap.bytes)+1)
  cap.hashBytes = ByteLimit(info.hashBytes-1)
  expect(prepareAvailabilityCommitment(original, cap), AvailabilityCommitmentError.LimitExceeded)
  cap.hashBytes = ByteLimit(info.hashBytes)
  cap.hashes = ElementLimit(info.hashes-1)
  expect(prepareAvailabilityCommitment(original, cap), AvailabilityCommitmentError.LimitExceeded)
  expect(done.availabilityShard(ErasureShardIndex(validators)),
      AvailabilityCommitmentError.InvalidIndex)
  expect(done.availabilityShard(ErasureShardIndex(high(uint64))),
      AvailabilityCommitmentError.InvalidIndex)
  done
let emptySource = source(0, 6)
let empty = verify(emptySource, EmptyBundle, EmptyWire, EmptyFirst, EmptyLast, EmptyCalls,
    EmptyHashBytes)
assert empty.availabilityInfo.value.hashes == 11, "six bundle hashes plus five raw-pair node hashes"
let singleSource = source(1)
let single = verify(singleSource, SingleBundle, SingleWire, SingleFirst, SingleLast, SingleCalls,
    SingleHashBytes)
discard verify(source(3), MixedBundle, MixedWire, MixedFirst, MixedLast, MixedCalls, MixedHashBytes)
discard verify(source(65, 6), PagedBundle, PagedWire, PagedFirst, PagedLast, PagedCalls, PagedHashBytes)
# Copied metadata and validator hashes cannot mutate retained root authority or original source provenance.
var copied = single.availabilityInfo.value
copied.specifier.erasureRoot.bytes[0] = copied.specifier.erasureRoot.bytes[0] xor 1
copied.specifier.packageHash.bytes[0] = copied.specifier.packageHash.bytes[0] xor 1
assert wire(single.availabilityInfo.value.specifier) == SingleWire, "availability field copy isolation"
var shard = single.availabilityShard(ErasureShardIndex(0)).value
shard.bundleHash = Blake2bHash(default(array[32, byte]))
assert pair(single.availabilityShard(ErasureShardIndex(0)).value) == SingleFirst, "validator hash copy isolation"
expect(default(AvailabilityCommitment).availabilityInfo, AvailabilityCommitmentError.Uninitialized)
expect(default(AvailabilityCommitment).availabilitySource,
    AvailabilityCommitmentError.Uninitialized)
expect(default(AvailabilityCommitment).availabilityShard(ErasureShardIndex(0)),
    AvailabilityCommitmentError.Uninitialized)
expect(default(AvailabilityCommitmentResult[AvailabilityCommitment]),
    AvailabilityCommitmentError.Uninitialized)
expect(prepareAvailabilityCommitment(default(ExportErasure), AvailabilityCommitmentLimits()),
    AvailabilityCommitmentError.InvalidSource)
# Refused aggregate policies must fail before any hashing, even when the backend is unavailable.
reset(1)
var cap = generous()
cap.bytes = ByteLimit(0)
expect(prepareAvailabilityCommitment(singleSource, cap), AvailabilityCommitmentError.LimitExceeded)
cap = generous()
cap.hashes = ElementLimit(0)
expect(prepareAvailabilityCommitment(singleSource, cap), AvailabilityCommitmentError.LimitExceeded)
cap = generous()
cap.hashBytes = ByteLimit(0)
expect(prepareAvailabilityCommitment(singleSource, cap), AvailabilityCommitmentError.LimitExceeded)
assert hashes() == 0, "all complete policies preflight before hashing"
expect(prepareAvailabilityCommitment(singleSource, generous()),
    AvailabilityCommitmentError.BackendFailure)
# Refuse the export subtree, a later validator, the first outer node and the final root after real successful child work.
for completed in [1'u64, 2, 2046, SingleCalls-1]:
  afterCalls(cint(completed))
  expect(prepareAvailabilityCommitment(singleSource, generous()),
      AvailabilityCommitmentError.BackendFailure)
  assert uint64(hashes()) == completed+1, "bounded actual late-backend failure"
reset(0)
proc detached(): AvailabilityCommitment =
  ## Retain complete availability and original execution after every local source handle retires.
  prepareAvailabilityCommitment(source(0, 6), generous()).value
assert wire(detached().availabilityInfo.value.specifier) == EmptyWire, "detached complete source lifetime"
proc cycle() =
  ## Release successful leaves and partially populated validator buffers on each ARC iteration.
  let done = prepareAvailabilityCommitment(emptySource, generous()).value
  assert wire(done.availabilityInfo.value.specifier) == EmptyWire, "ARC genuine complete root control"
  afterCalls(2)
  expect(prepareAvailabilityCommitment(emptySource, generous()),
      AvailabilityCommitmentError.BackendFailure)
  reset(0)
  expect(prepareAvailabilityCommitment(emptySource, AvailabilityCommitmentLimits()),
      AvailabilityCommitmentError.LimitExceeded)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "availability commitment ARC release"
recordArcRelease("pvm_availability_specifier", 1000, before, after)
echo "PVM availability specifier passed"
echo "ARC_RELEASE cycles=1000 unchanged"
