# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_auditable_bundle_arc_release"}

## Independent full-wire witnesses, exact budgets and immutable original execution provenance.

import std/[assertions, syncio]
import ../../../src/state/[auditable_bundle, audit_bundle, input_refinement]
import "../../../src/state/import/inputs" as import_inputs
import ../../../src/state/[extrinsic_inputs, authorized_refinement]
import ../../../src/state/authorization/invocation
import ../../../src/state/refinement/digest
import ../../../src/state/report/identity as report_identity
import ../../../src/codec/bounded
import ../../../src/codec/work/[report as work_report, package as work_package]
import ../../../src/pvm/host/fetch as host_fetch
import "../../../src/state/import/justification" as import_justification
import ../../../src/crypto/primitives
import ../../support/pvm_input_refinement
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

proc decodingLimits(): AuditBundleLimits =
  ## Explicit independent limits cover the literal ordinary/rich witnesses without unbounded decoder scratch or crypto.
  AuditBundleLimits(package: fullPackageConfig(ByteLimit(8192)), extrinsics: ElementLimit(16),
    imports: ElementLimit(16), hashes: ElementLimit(64), bytes: ByteLimit(32768),
    workspaceBytes: ByteLimit(8*1024*1024), hashBytes: ByteLimit(128000))
proc decoded(source: InputRefinement, bundle: AuditableBundle): DecodedAuditBundle =
  ## Decode actual assembled bytes and compare every retained original occurrence, including repeated and empty rows, without accepting a replaceable package or proof.
  let info = bundle.bundleInfo.value
  let wire = bundle.bundleBytes.value
  let original = source.inputRefinementSource.value
  let lookup = original.importInputsLookup.value
  let header = ReportHeader(packageHash: info.packageHash, bundleLength: info.length)
  let outcome = decodeAuditBundle(wire, header, lookup, decodingLimits())
  assert outcome.error == AuditBundleError.None, "complete input commitment decoding: " & $outcome.error
  let inputs = outcome.value.decodedInputs.value
  let described = inputs.importInputsInfo.value
  let expected = original.importInputsInfo.value
  assert described.items == expected.items and described.entries == expected.entries and
    described.lookupCount == expected.lookupCount and described.witnessBytes ==
        expected.witnessBytes, "original manifest and dictionary geometry"
  let oldExtrinsics = original.importInputsExtrinsics.value
  let newExtrinsics = inputs.importInputsExtrinsics.value
  let package = oldExtrinsics.extrinsicInputsPackage.value
  for item in 0..<described.items:
    let entry = package.workItemAt(item).value.workItemInfo.value
    for ordinal in 0..<entry.extrinsics:
      assert oldExtrinsics.extrinsicInput(FetchItemIndex(uint64(item)), ExtrinsicInputIndex(uint64(
          ordinal))).value ==
        newExtrinsics.extrinsicInput(FetchItemIndex(uint64(item)), ExtrinsicInputIndex(uint64(
            ordinal))).value, "raw extrinsic occurrence remains package-bound"
    for ordinal in 0..<entry.imports:
      let before = original.importInput(FetchItemIndex(uint64(item)), ImportInputIndex(uint64(
          ordinal))).value
      let after = inputs.importInput(FetchItemIndex(uint64(item)), ImportInputIndex(uint64(
          ordinal))).value
      assert array[4104, byte](before.verifiedImportSegment.value) == array[4104, byte](
          after.verifiedImportSegment.value), "original imported segment occurrence"
      assert before.verifiedImportProof.value == after.verifiedImportProof.value, "original root-first proof occurrence"
  return outcome.value
proc replayDecoded(source: InputRefinement, bundle: AuditableBundle) =
  ## Execute decoded commitments against the original real complete state and parameters; every final digest byte and authorization trace must reproduce, rather than trusting a caller's expected validity bit.
  let identity = source.inputRefinementIdentity.value
  let original = identity.identitySource.value
  let authorization = original.authorizedSource.value
  let inputs = decoded(source, bundle).decodedInputs.value
  let executed = runInputRefinement(authorization.authorizationState.value, inputs,
    identity.identityInfo.value.core, authorization.authorizationParameters.value, executionLimits())
  assert executed.error == InputRefinementError.None, "actual decoded-input guest execution: " &
      $executed.error
  let reproduced = executed.value.inputRefinementIdentity.value.identitySource.value
  assert reproduced.authorizedSource.value.authorizationTrace.value ==
      authorization.authorizationTrace.value, "whole authorization trace reproduction"
  let before = original.authorizedDigests.value
  let after = reproduced.authorizedDigests.value
  assert before.digestCount.value == after.digestCount.value, "whole reproduced item population"
  for ordinal in 0..<before.digestCount.value:
    assert before.digestAt(FetchItemIndex(uint64(ordinal))).value.digestBytes.value ==
      after.digestAt(FetchItemIndex(uint64(ordinal))).value.digestBytes.value, "actual complete canonical item digest reproduction"
  assert prepareAuditableBundle(executed.value, ByteLimit(32768)).value.bundleBytes.value ==
      bundle.bundleBytes.value, "executed decoded inputs reassemble the exact original bundle"
proc decodingFailures(source: InputRefinement, bundle: AuditableBundle) =
  ## Untrusted section boundaries, commitments, canonical path counts and whole-work policies produce precise failures without authenticated prefixes.
  let info = bundle.bundleInfo.value
  let wire = bundle.bundleBytes.value
  let lookup = source.inputRefinementSource.value.importInputsLookup.value
  let header = ReportHeader(packageHash: info.packageHash, bundleLength: info.length)
  for cut in [0, int(info.packageBytes)-1, int(info.packageBytes+info.extrinsicBytes)-1,
      int(info.packageBytes+info.extrinsicBytes+info.segmentBytes)-1, wire.len-1]:
    var shortened = header
    shortened.bundleLength = BundleLength(uint32(cut))
    let incomplete = decodeAuditBundle(wire.toOpenArray(0, cut-1), shortened, lookup,
        decodingLimits())
    assert incomplete.error != AuditBundleError.None, "every incomplete section refuses the whole bundle"
  var changed = header
  changed.packageHash.bytes[0] = changed.packageHash.bytes[0] xor 1
  assert decodeAuditBundle(wire, changed, lookup, decodingLimits()).error ==
      AuditBundleError.PackageHashMismatch, "actual canonical package hash precedes table authentication"
  changed = header
  changed.bundleLength = BundleLength(uint32(wire.len-1))
  assert decodeAuditBundle(wire, changed, lookup, decodingLimits()).error ==
      AuditBundleError.LengthMismatch, "exact declared bundle extent"
  var damaged = wire
  damaged[int(info.packageBytes)] = damaged[int(info.packageBytes)] xor 1
  let badExtrinsic = decodeAuditBundle(damaged, header, lookup, decodingLimits())
  assert badExtrinsic.error == AuditBundleError.ExtrinsicFailure and badExtrinsic.extrinsicError ==
      ExtrinsicInputsError.HashMismatch, "actual raw preimage commitment refusal"
  damaged = wire
  let segmentStart = int(info.packageBytes+info.extrinsicBytes)
  damaged[segmentStart] = damaged[segmentStart] xor 1
  let badSegment = decodeAuditBundle(damaged, header, lookup, decodingLimits())
  assert badSegment.error == AuditBundleError.ImportFailure and badSegment.importError ==
      ImportJustificationError.RootMismatch, "actual imported leaf inclusion refusal"
  damaged = wire
  damaged[segmentStart+int(info.segmentBytes)] = 13
  assert decodeAuditBundle(damaged, header, lookup, decodingLimits()).error ==
      AuditBundleError.InvalidProof, "path count is one canonical byte in0..12"
  damaged = wire
  damaged.add(0)
  changed = header
  changed.bundleLength = BundleLength(uint32(damaged.len))
  assert decodeAuditBundle(damaged, changed, lookup, decodingLimits()).error ==
      AuditBundleError.TrailingBytes, "declared padding cannot follow the last proof"
  var limited = decodingLimits()
  limited.hashes = ElementLimit(8) # Independent ordinary witness: one package, two extrinsics and two three-hash inclusion proofs require nine hashes.
  reset(0)
  assert decodeAuditBundle(wire, header, lookup, limited).error ==
      AuditBundleError.LimitExceeded and hashes() == 0, "whole hash reservation precedes every primitive call"
  limited = decodingLimits()
  limited.hashBytes = ByteLimit(info.packageBytes+8493) # Two3-byte preimages, two4108-byte leaves and four68-byte nodes add8494 bytes to the canonical package.
  assert decodeAuditBundle(wire, header, lookup, limited).error ==
      AuditBundleError.LimitExceeded and hashes() == 0, "whole hash-preimage byte reservation"
  reset(1)
  let backend = decodeAuditBundle(wire, header, lookup, decodingLimits())
  assert backend.error == AuditBundleError.HashFailure and backend.hashError ==
      CryptoError.BackendFailure, "native backend refusal cannot classify a report as invalid"
  reset(0)
  assert default(DecodedAuditBundle).decodedInputs.error == AuditBundleError.Uninitialized, "default is not verified input ownership"

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
reset(0)
let decodedOrdinary = decoded(source, bundle)
assert decodedOrdinary.decodedInfo.value.hashes == 9 and hashes() == 9, "independent ordinary primitive work count"
assert decodedOrdinary.decodedInfo.value.hashBytes == uint64(OrdinaryPackage.len)+8494, "independent ordinary preimage byte count"
decodingFailures(source, bundle)
replayDecoded(source, bundle)
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
reset(0)
let decodedRich = decoded(richSource, rich)
assert decodedRich.decodedInfo.value.hashes == 14 and hashes() == 14, "empty and repeated rich occurrences each consume their own hash"
assert decodedRich.decodedInfo.value.hashBytes == uint64(RichPackage.len)+17089, "independent rich preimage byte count"
replayDecoded(richSource, rich)
let emptySource = bundleExecution(exports = true)
let emptyBundle = prepareAuditableBundle(emptySource, ByteLimit(32768)).value
let empty = decoded(emptySource, emptyBundle)
replayDecoded(emptySource, emptyBundle)
assert empty.decodedInfo.value.imports == 0 and empty.decodedInfo.value.extrinsics == 0, "empty tables still derive a real package-bound certificate"
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
  assert decoded(source, done).decodedInfo.value.imports == 2, "ARC cycle actual commitment decoding"
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
