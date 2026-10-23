# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_auditable_bundle_arc_release"}

## Independent full-wire witnesses, exact budgets and immutable original execution provenance.

import std/[assertions, syncio]
import ../../../src/state/[auditable_bundle, input_refinement, import_inputs, extrinsic_inputs,
  authorized_refinement, report_identity]
import ../../../src/codec/[bounded, work_report]
import ../../../src/crypto/primitives
import ../../support/[pvm_auditable_bundle, pvm_bundle_vectors, pvm_import_vectors, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse primitive work after original execution to prove assembly is pure serialization.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe exact copied counters without inventing a backend success.
proc expect[T](outcome: AuditableBundleResult[T], reason: AuditableBundleError) =
  ## Check precise alternatives without extracting a refused partial bundle.
  assert outcome.error == reason, "auditable bundle reason"
proc samePrefix(bytes: openArray[byte], prefix: openArray[byte]): bool =
  ## Compare independently frozen canonical package bytes without production re-encoding.
  if bytes.len < prefix.len: return false
  for index in 0..<prefix.len:
    if bytes[index] != prefix[index]: return false # First differing wire byte rejects the complete expected prefix.
  true

let source = bundleExecution()
let bundle = prepareAuditableBundle(source, ByteLimit(OrdinaryLength)).value
let info = bundle.bundleInfo.value
let wire = bundle.bundleBytes.value
assert samePrefix(wire, OrdinaryPackage), "independent ordinary package wire"
assert wire.len == OrdinaryLength, "ordinary bundle length"
assert uint32(info.length) == uint32(OrdinaryLength), "nominal bundle length"
assert info.packageBytes == uint64(OrdinaryPackage.len), "ordinary package size"
assert info.extrinsicBytes == uint64(OrdinaryExtrinsicBytes), "ordinary extrinsic size"
assert info.segmentBytes == uint64(OrdinarySegmentBytes), "ordinary segment size"
assert info.proofBytes == uint64(OrdinaryProofBytes), "ordinary proof size"
assert array[32, byte](blake2b256(wire).value) == OrdinaryHash, "independent ordinary full bundle hash"
assert info.packageHash.bytes == source.inputRefinementIdentity.value.identityInfo.value.packageHash.bytes, "original executed package hash"
let base = int(info.packageBytes)
assert samePrefix(wire.toOpenArray(base, base+5), [97'u8, 98, 99, 97, 98, 100]), "all raw extrinsics precede imports without prefixes"
assert wire[base+6] == 1 and wire[base+6+4104] == 2, "ordered imported leaf bytes"
let proofStart = base+6+8208
assert wire[proofStart] == 2 and wire[proofStart+65] == 2, "only Merkle paths have count prefixes"
for index in 0..<32:
  assert wire[proofStart+1+index] == ThreePath0[0][index], "root-first proof order"
  assert wire[proofStart+33+index] == ThreePath0[1][index], "leaf-level proof order"
# Every section boundary is covered by the one retained-output policy, including the complete final proof byte.
for bytes in [0'u64, info.packageBytes-1, info.packageBytes+info.extrinsicBytes-1,
  info.packageBytes+info.extrinsicBytes+info.segmentBytes-1, uint64(OrdinaryLength-1)]:
  expect(prepareAuditableBundle(source, ByteLimit(bytes)), AuditableBundleError.LimitExceeded)
expect(prepareAuditableBundle(source, ByteLimit(high(uint64))), AuditableBundleError.None)
# Empty rows/preimages add no framing; repeated raw inputs and singleton E(0) paths retain their occurrences.
let richSource = bundleExecution(rich = true)
let rich = prepareAuditableBundle(richSource, ByteLimit(RichLength)).value
let richInfo = rich.bundleInfo.value
let richWire = rich.bundleBytes.value
assert samePrefix(richWire, RichPackage), "independent rich package wire"
assert richWire.len == RichLength, "rich bundle length"
assert richInfo.extrinsicBytes == uint64(RichExtrinsicBytes), "128/129-byte raw inputs"
assert richInfo.segmentBytes == uint64(RichSegmentBytes), "rich segment extent"
assert richInfo.proofBytes == uint64(RichProofBytes), "singleton and repeated paths"
assert array[32, byte](blake2b256(richWire).value) == RichHash, "independent rich full bundle hash"
let dataStart = RichPackage.len
for index in 0..<128: assert richWire[dataStart+index] == 7, "no blob length discriminator at 128"
for index in 0..<129: assert richWire[dataStart+128+index] == 8, "no blob length discriminator at 129"
for index in 0..<128: assert richWire[dataStart+257+index] == 7, "duplicate extrinsic occurrence"
let richProofStart = dataStart+385+4*4104
assert richWire[richProofStart] == 0, "singleton proof includes canonical E(0)"
assert richWire[richProofStart+1] == 2, "path after singleton has its own prefix"
assert richWire[richProofStart+66] == 2, "empty item row introduces no prefix"
assert richWire[richProofStart+131] == 0, "repeated singleton retains E(0)"
expect(prepareAuditableBundle(richSource, ByteLimit(RichLength-1)),
    AuditableBundleError.LimitExceeded)
# Successful exports are retained by execution, but the bundle contains only the original package when input tables are empty.
let exported = bundleExecution(exports = true)
assert uint64(exported.inputRefinementIdentity.value.identitySource.value.authorizedInfo.value.exports) ==
    1, "real export control"
let packageOnly = prepareAuditableBundle(exported, ByteLimit(4096)).value
let packageInfo = packageOnly.bundleInfo.value
assert uint64(uint32(packageInfo.length)) == packageInfo.packageBytes, "exports and trace are not extra bundle fields"
assert packageInfo.extrinsicBytes == 0 and packageInfo.segmentBytes == 0 and
    packageInfo.proofBytes == 0, "empty tables add no bytes"
# No new hashing occurs even when the backend is unavailable; source selection precedes all local allocation policies.
reset(1)
expect(prepareAuditableBundle(source, ByteLimit(OrdinaryLength)), AuditableBundleError.None)
expect(prepareAuditableBundle(source, ByteLimit(0)), AuditableBundleError.LimitExceeded)
expect(prepareAuditableBundle(default(InputRefinement), ByteLimit(0)),
    AuditableBundleError.InvalidSource)
assert hashes() == 0, "bundle assembly performs no hashing"
reset(0)
expect(default(AuditableBundle).bundleInfo, AuditableBundleError.Uninitialized)
expect(default(AuditableBundle).bundleSource, AuditableBundleError.Uninitialized)
expect(default(AuditableBundle).bundleBytes, AuditableBundleError.Uninitialized)
# Byte and metadata copies cannot modify retained bytes or package provenance; replay consumes the original source owner.
var copied = bundle.bundleBytes.value
copied[0] = copied[0] xor 1
var copiedInfo = bundle.bundleInfo.value
copiedInfo.length = BundleLength(0)
copiedInfo.packageHash.bytes[0] = copiedInfo.packageHash.bytes[0] xor 1
assert bundle.bundleBytes.value == wire, "bundle byte copy isolation"
assert uint32(bundle.bundleInfo.value.length) == uint32(OrdinaryLength), "bundle metadata copy isolation"
let replay = prepareAuditableBundle(bundle.bundleSource.value, ByteLimit(OrdinaryLength)).value
assert replay.bundleBytes.value == wire, "replay preserves original executed inputs"
proc detached(): AuditableBundle =
  ## Retire original code/state/input/execution temporaries before extracting the retained auditable bytes.
  prepareAuditableBundle(bundleExecution(), ByteLimit(OrdinaryLength)).value
assert detached().bundleBytes.value == wire, "detached bundle lifetime"
proc cycle() =
  ## Release owned buffers and extracted copies while retaining no successful prefix from refused local candidates.
  let done = prepareAuditableBundle(source, ByteLimit(OrdinaryLength)).value
  assert done.bundleBytes.value == wire, "ARC cycle complete bytes"
  expect(prepareAuditableBundle(source, ByteLimit(OrdinaryLength-1)),
      AuditableBundleError.LimitExceeded)
cycle()
let before = getOccupiedMem()
for iteration in 0..<1000: cycle()
let after = getOccupiedMem()
assert before == after, "auditable bundle ARC release"
recordArcRelease("pvm_auditable_bundle", 1000, before, after)
echo "PVM auditable bundle passed"
echo "ARC_RELEASE cycles=1000 unchanged"
