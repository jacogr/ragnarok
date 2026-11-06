# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_assurance_record_arc_release"}

## Genuine CE137 data tests complete persistent-record restart verification, fixed-time promises, aggregate preflight and independent canonical metadata binding.
import std/[assertions, syncio]
import ../../../src/jamnp-s/[assurance_record, availability_proof, availability_merkle]
import ../../../src/state/availability/specifier
import ../../../src/state/erasure/words
import ../../../src/codec/bounded
import ../../../src/codec/work/report
import ../../../src/crypto/primitives
import ../../support/[pvm_computed_report, arc_evidence]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset actual primitive counts and optional backend refusal for one isolated sequential witness.
proc after(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Fail after an observed successful metadata checksum to preserve a genuine payload child failure.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe attempted maintained Blake2b calls without replacing any protocol calculation.
proc limits(): AssuranceRecordLimits =
  ## Separate serialized bytes and exact checksum/proof work remain explicit test-only inputs.
  AssuranceRecordLimits(bytes: ByteLimit(16000000), verification: AvailabilityMerkleLimits(
    bytes: ByteLimit(64000000), hashes: ElementLimit(10000), hashBytes: ByteLimit(64000000)))
proc chain(): AssuranceChainId =
  ## The expected chain is selected independently of a persistence record and its shard root.
  var bytes = default(array[32, byte])
  bytes[0] = 29
  AssuranceChainId(bytes)
proc transfer(kind: int, shards: uint16): VerifiedAvailabilityTransfer =
  ## Only detached verified bytes survive the genuine execution/erasure source; no report session is retained by a record.
  let source = computedAvailabilityAtCore(kind, 1, shards)
  let expected = source.availabilityInfo.value.specifier
  let request = AvailabilityRequest(kind: AvailabilityTransferKind.Distribution,
    root: expected.erasureRoot, shard: ErasureShardIndex(uint64(shards)-1))
  let prepared = prepareAvailabilityTransfer(source, request, limits().verification)
  assert prepared.error == AvailabilityTransferError.None, "prepare distribution: " &
      $prepared.error
  let packet = prepared.value
  let verified = verifyAvailabilityTransfer(expected, request, packet.bundleShard,
    packet.segmentShards, packet.justification, limits().verification)
  assert verified.error == AvailabilityTransferError.None, "verify distribution: " & $verified.error
  verified.value
proc check(source: VerifiedAvailabilityTransfer) =
  ## Empty, odd and proof-page row geometries must survive exact metadata serialization and full proof re-verification.
  let made = prepareAssuranceRecord(source, chain(), AssuranceTime(1000), limits())
  assert made.error == AssuranceRecordError.None, "record preparation: " & $made.error
  let record = made.value
  let info = record.recordInfo.value
  assert uint64(info.promisedAt) == 1000 and uint64(info.retainUntil) == 1000'u64+2419200, "28 days are seconds for every erasure profile"
  assert record.recordMatches(source.specifier, source.request), "exact independent source binding"
  let encoded = encodeAssuranceRecord(record, limits())
  assert encoded.error == AssuranceRecordError.None, "complete record encoding"
  let wire = encoded.value
  assert uint64(wire.len) == info.encodedBytes, "exact encoded extent"
  assert wire[0] == byte('R') and wire[7] == byte('1'), "physical schema literal"
  assert wire[8] == 29 and wire[40] == source.specifier.packageHash.bytes[0], "chain and package offsets"
  let metadata = inspectAssuranceRecord(wire.toOpenArray(0, AssuranceRecordHeaderBytes-1), chain(),
      limits())
  assert metadata.error == AssuranceRecordError.None, "metadata checksum for bounded directory scan"
  assert metadata.value.encodedBytes == uint64(wire.len), "metadata cannot hide trailing payload"
  let plan = availabilityVerificationInfo(source.specifier, source.request).value
  var exact = limits()
  exact.bytes = ByteLimit(wire.len)
  exact.verification.bytes = ByteLimit(plan.payloadBytes*3+uint64(AssuranceRecordHeaderBytes))
  exact.verification.hashes = ElementLimit(plan.hashes+1)
  exact.verification.hashBytes = ByteLimit(plan.hashBytes+174)
  reset(0)
  let restored = decodeAssuranceRecord(wire, chain(), exact)
  assert restored.error == AssuranceRecordError.None, "exact complete restore budgets: " &
      $restored.error
  assert uint64(calls()) == plan.hashes+1, "one metadata checksum plus exact real proof verification"
  assert restored.value.recordMatches(source.specifier, source.request), "restored canonical coordinate"
  let copied = restored.value.recordTransfer(ByteLimit(plan.payloadBytes))
  assert copied.error == AvailabilityTransferError.None, "source-free verified serving copy"
  assert copied.value.bundleShard == source.bundleShard and copied.value.segmentShards ==
      source.segmentShards and copied.value.justification == source.justification, "all three exact CE137 payloads"
  assert encodeAssuranceRecord(restored.value, limits()).value == wire, "canonical byte round trip"
  var wrong = source.specifier
  wrong.packageHash.bytes[0] = wrong.packageHash.bytes[0] xor 1
  assert not restored.value.recordMatches(wrong, source.request), "equal root cannot replace package identity"
  wrong = source.specifier
  wrong.segmentRoot.bytes[0] = wrong.segmentRoot.bytes[0] xor 1
  assert not restored.value.recordMatches(wrong, source.request), "equal root cannot replace export context"
  var request = source.request
  request.shard = ErasureShardIndex(0)
  assert not restored.value.recordMatches(source.specifier, request), "foreign shard cannot claim assigned possession"
  for field in 0..<4:
    # Every aggregate deficit must refuse before the metadata hash, including when the individual child budget alone would fit.
    var narrow = exact
    case field
    of 0: narrow.bytes = ByteLimit(uint64(exact.bytes)-1)
    of 1: narrow.verification.bytes = ByteLimit(uint64(exact.verification.bytes)-1)
    of 2: narrow.verification.hashes = ElementLimit(uint64(exact.verification.hashes)-1)
    else: narrow.verification.hashBytes = ByteLimit(uint64(exact.verification.hashBytes)-1)
    reset(0)
    assert decodeAssuranceRecord(wire, chain(), narrow).error == AssuranceRecordError.LimitExceeded, "whole record budget deficit"
    assert calls() == 0, "whole preflight must precede even the metadata checksum"
  let renewed = renewAssuranceRecord(record, AssuranceTime(2000), limits())
  assert renewed.error == AssuranceRecordError.None, "later promise renewal"
  assert uint64(renewed.value.recordInfo.value.retainUntil) >= uint64(info.retainUntil), "renewal never shortens a promise"
  assert uint64(record.recordInfo.value.promisedAt) == 1000, "renewal preserves immutable original"
  assert renewAssuranceRecord(record, AssuranceTime(999), limits()).error ==
      AssuranceRecordError.InvalidTime, "backwards renewal refused"
proc malformed(source: VerifiedAvailabilityTransfer) =
  ## A valid stored checksum alone cannot substitute for payload proof verification or exact independent expected chain/shape.
  let made = prepareAssuranceRecord(source, chain(), AssuranceTime(1000), limits()).value
  let encoded = encodeAssuranceRecord(made, limits()).value
  assert decodeAssuranceRecord([], chain(), limits()).error == AssuranceRecordError.InvalidFormat, "empty record refused"
  for length in 1..<AssuranceRecordHeaderBytes:
    # Every incomplete fixed metadata prefix fails before any unbounded extent or hash.
    reset(0)
    assert decodeAssuranceRecord(encoded.toOpenArray(0, length-1), chain(), limits()).error ==
        AssuranceRecordError.InvalidFormat, "truncated fixed header"
    assert calls() == 0, "truncated header performs no primitive work"
  reset(0)
  assert decodeAssuranceRecord(encoded.toOpenArray(0, encoded.len-2), chain(), limits()).error ==
      AssuranceRecordError.InvalidFormat, "truncated final proof"
  assert calls() == 0, "exact EOF precedes checksum"
  var wire = encoded
  wire.add(0)
  reset(0)
  assert decodeAssuranceRecord(wire, chain(), limits()).error == AssuranceRecordError.InvalidFormat, "trailing payload refused"
  assert calls() == 0, "trailing extent preflight"
  var other = array[32, byte](chain())
  other[0] = 30
  assert decodeAssuranceRecord(encoded, AssuranceChainId(other), limits()).error ==
      AssuranceRecordError.WrongChain, "independent expected chain"
  wire = encoded
  wire[40] = wire[40] xor 1
  assert decodeAssuranceRecord(wire, chain(), limits()).error ==
      AssuranceRecordError.ChecksumMismatch, "metadata integrity"
  wire = encoded
  wire[AssuranceRecordHeaderBytes] = wire[AssuranceRecordHeaderBytes] xor 1
  let damaged = decodeAssuranceRecord(wire, chain(), limits())
  assert damaged.error == AssuranceRecordError.TransferFailure, "payload corruption must reverify actual inclusion"
  assert damaged.transferError.error == AvailabilityTransferError.MerkleFailure, "preserve actual Merkle child refusal"
  assert damaged.transferError.merkleError == AvailabilityMerkleError.RootMismatch, "preserve actual root mismatch"
  reset(1)
  assert decodeAssuranceRecord(encoded, chain(), limits()).error ==
      AssuranceRecordError.BackendFailure, "real metadata hash refusal"
  assert calls() == 1, "first checksum attempt"
  after(1)
  let failed = decodeAssuranceRecord(encoded, chain(), limits())
  assert failed.error == AssuranceRecordError.TransferFailure, "real payload backend child refusal"
  assert failed.transferError.error == AvailabilityTransferError.BackendFailure, "actual failed proof backend child"
  reset(0)
  assert decodeAssuranceRecord(encoded, chain(), limits()).error == AssuranceRecordError.None, "recovery after backend failure"
  assert prepareAssuranceRecord(source, chain(), AssuranceTime(high(
      uint64)-AssuranceRetentionSeconds+1), limits()).error == AssuranceRecordError.InvalidTime, "retention addition overflow"
  let edge = prepareAssuranceRecord(source, chain(), AssuranceTime(high(
      uint64)-AssuranceRetentionSeconds), limits())
  assert edge.error == AssuranceRecordError.None, "exact last representable promise"
  assert uint64(edge.value.recordInfo.value.retainUntil) == high(uint64), "full-width exact retention boundary"
proc cycle(source: VerifiedAvailabilityTransfer) =
  ## Record construction, independent restoration, serving extraction and late budget refusal all retire before ARC comparison.
  let record = prepareAssuranceRecord(source, chain(), AssuranceTime(1000), limits()).value
  let wire = encodeAssuranceRecord(record, limits()).value
  let restored = decodeAssuranceRecord(wire, chain(), limits())
  assert restored.error == AssuranceRecordError.None, "ARC restore"
  assert restored.value.recordTransfer(ByteLimit(16000000)).error == AvailabilityTransferError.None, "ARC serving extraction"
  var narrow = limits()
  narrow.verification.hashes = ElementLimit(1)
  assert decodeAssuranceRecord(wire, chain(), narrow).error == AssuranceRecordError.LimitExceeded, "ARC late aggregate refusal"
proc main() =
  ## Real erasure sources cover empty, ordinary and proof-page distributions; no filesystem or signature authority is inferred from this codec suite.
  assert not default(AssuranceRecord).valid, "default record disabled"
  assert prepareAssuranceRecord(default(VerifiedAvailabilityTransfer), chain(), AssuranceTime(0),
      limits()).error == AssuranceRecordError.InvalidSource, "default transfer refused"
  check(transfer(0, 6))
  let source = transfer(1, 1023)
  check(source)
  check(transfer(65, 12))
  malformed(source)
  cycle(source)
  let before = getOccupiedMem()
  for index in 0..<1000:
    # Complete successful and refused record owners must release every private byte copy.
    cycle(source)
  let afterBytes = getOccupiedMem()
  assert before == afterBytes, "persistent assurance record ARC release"
  recordArcRelease("jamnp_assurance_record", 1000, before, afterBytes)
  echo "JAMNP-S assurance record passed"
main()
