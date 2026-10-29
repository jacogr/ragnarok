# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_envelope_arc_release"}

## Exact standalone wire, independent key order, reporter identity deduplication and immutable owner lifetime.

import std/[assertions, syncio]
import ../../../src/state/computed/[envelope as computed_envelope,
    credentials as computed_credentials, guarantors as computed_guarantors,
    roster as computed_roster, transition as computed_transition, profile as computed_profile,
    lookup as computed_lookup, recent as computed_recent, state as computed_state,
    links as computed_links, guarantee as computed_guarantee, report as computed_report]
import ../../../src/state/store
import ../../../src/codec/[bounded, assurances, guarantees, report_owned, owned]
import ../../../src/codec/state/safrole as state_safrole
import ../../support/[pvm_computed_envelope, pvm_computed_credentials, report_context, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse new hashing after real original computation, credentials and native signature checks complete.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe actual hash attempts during materialization and output queries.
proc expect[T](outcome: ComputedEnvelopeResult[T], reason: ComputedEnvelopeError) =
  ## Compare exact selected alternatives before guarded extraction.
  assert outcome.error == reason, "computed envelope reason: " & $outcome.error
proc originalWire(source: CredentialedComputedReport): seq[byte] =
  ## Recover exact original canonical report bytes through complete credential/computation provenance.
  let context = source.computedCredentialSource.value
  let transcript = context.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value.computedStateSource.value.computedLinkSource.value
  transcript.computedGuaranteeReport.value.computedReportBytes.value
proc cap(source: CredentialedComputedReport, reporters = 3'u64): ComputedEnvelopeLimits =
  ## Independent literal standalone suffix width is E4 plus one count octet plus66 bytes per credential.
  let report = originalWire(source)
  let count = source.computedCredentialInfo.value.credentials
  ComputedEnvelopeLimits(reportBytes: ByteLimit(uint64(report.len)),
    bytes: ByteLimit(uint64(report.len+5+66*count)), reporters: ElementLimit(reporters))
proc independentWire(source: CredentialedComputedReport): seq[byte] =
  ## Assemble the protocol tuple explicitly without calling any guarantee encoder.
  result = originalWire(source)
  let info = source.computedCredentialInfo.value
  for i in 0..<4: result.add(byte((uint32(info.slot) shr (8*i)) and 255)) # Literal E4 little-endian slot.
  result.add(byte(info.credentials)) # Count2/3 has exactly one canonical octet, without an outer list count.
  for i in 0..<info.credentials:
    let record = source.computedCredentialAt(ComputedCredentialIndex(uint64(i))).value
    let index = uint16(record.validator)
    result.add(byte(index and 255))
    result.add(byte(index shr 8)) # Index is E2 even when its value would fit one compact octet.
    for octet in array[64, byte](record.signature): result.add(octet) # Preserve every verified signature byte.
proc key(text: string): array[32, byte] =
  ## Literal public-key references independently generated with OpenSSL Ed25519 PKCS8 seed import.
  result = default(array[32, byte])
  let bytes = unhex(text)
  assert bytes.len == 32
  for i in 0..<32: result[i] = bytes[i]
let source = envelopeFixture()
let limits = cap(source, 2)
let done = prepareComputedEnvelope(source, limits).value
let expected = independentWire(source)
let actual = done.computedEnvelopeBytes.value
assert actual == expected, "independent exact standalone wire tuple"
assert uint64(limits.bytes) == uint64(actual.len)
assert done.computedEnvelopeInfo.value.bytes == uint64(actual.len)
assert done.computedEnvelopeInfo.value.reportBytes == uint64(originalWire(source).len)
assert done.computedEnvelopeInfo.value.reporters == 2
let config = GuaranteeConfig(cores: CoreCount(3), validators: ValidatorCount(9),
    maxBytes: limits.bytes)
let decoded = decodeGuarantee(actual, config)
assert decoded.error == GuaranteeError.None and decoded.value.consumed == actual.len
assert encodeGuaranteeValue(decoded.value.value, config).value == actual, "canonical codec round trip"
let guarantee = done.computedEnvelopeGuarantee.value
assert uint32(guarantee.slot) == 2 and guarantee.credentialCount == 2
var reportCopy = newSeq[byte](int(done.computedEnvelopeInfo.value.reportBytes))
assert encodeOwnedReport(guarantee.report, reportCopy).error == OwnershipError.None
assert reportCopy == originalWire(source), "exact original report prefix"
let sourceContext = source.computedCredentialSource.value
let original = sourceContext.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.state
assert sameStateSnapshot(done.computedEnvelopeSource.value.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.state, original)
var shortReport = limits
shortReport.reportBytes = ByteLimit(uint64(limits.reportBytes)-1)
expect(prepareComputedEnvelope(source, shortReport), ComputedEnvelopeError.LimitExceeded)
var shortWire = limits
shortWire.bytes = ByteLimit(uint64(limits.bytes)-1)
expect(prepareComputedEnvelope(source, shortWire), ComputedEnvelopeError.LimitExceeded)
var shortSet = limits
shortSet.reporters = ElementLimit(1)
expect(prepareComputedEnvelope(source, shortSet), ComputedEnvelopeError.LimitExceeded)
expect(prepareComputedEnvelope(source, ComputedEnvelopeLimits()),
    ComputedEnvelopeError.LimitExceeded)
expect(prepareComputedEnvelope(default(CredentialedComputedReport), limits),
    ComputedEnvelopeError.InvalidSource)
expect(default(ComputedEnvelopeResult[ComputedGuaranteeEnvelope]),
    ComputedEnvelopeError.Uninitialized)
expect(default(ComputedGuaranteeEnvelope).computedEnvelopeSource,
    ComputedEnvelopeError.Uninitialized)
expect(default(ComputedGuaranteeEnvelope).computedEnvelopeInfo, ComputedEnvelopeError.Uninitialized)
expect(default(ComputedGuaranteeEnvelope).computedEnvelopeGuarantee,
    ComputedEnvelopeError.Uninitialized)
expect(default(ComputedGuaranteeEnvelope).computedEnvelopeBytes,
    ComputedEnvelopeError.Uninitialized)
expect(default(ComputedGuaranteeEnvelope).computedEnvelopeReporterAt(ComputedReporterIndex(0)),
    ComputedEnvelopeError.Uninitialized)
expect(done.computedEnvelopeReporterAt(ComputedReporterIndex(2)),
    ComputedEnvelopeError.InvalidIndex)
expect(done.computedEnvelopeReporterAt(ComputedReporterIndex(high(uint64))),
    ComputedEnvelopeError.InvalidIndex)
let tripleSource = envelopeFixture(triple = true)
let triple = prepareComputedEnvelope(tripleSource, cap(tripleSource)).value
assert triple.computedEnvelopeBytes.value == independentWire(tripleSource)
assert triple.computedEnvelopeInfo.value.reporters == 3
# A credential order of seeds11/14/15 must become lexicographic key order14/11/15.
let reorderedContext = credentialFixture(core = 1)
let reorderedRecords = signedCredentials(reorderedContext, GuaranteeSlot(2), [0'u16, 3, 4],
    credentialMessage(reorderedContext))
let reorderedSource = verifyComputedCredentials(reorderedContext, GuaranteeSlot(2),
    reorderedRecords).value
let reordered = prepareComputedEnvelope(reorderedSource, cap(reorderedSource)).value
let keys = [key("015743be93526e88156aa0a8349cd6b15344b28ae7f2ab3faf5e340b4a0c1ec4"),
  key("7380a4b28d0b49b46e7ca1e4369949c8eb733ff90b69b3530d7e83f073900979"),
  key("e8d8764d05e660a0228b6cb2cb05510e6786a90caa797a6b80f22336e9f9205f")]
for i in 0..<3:
  assert array[32, byte](reordered.computedEnvelopeReporterAt(ComputedReporterIndex(uint64(
      i))).value) == keys[i], "independent lexicographic reporter reference"
let repeatedSource = envelopeFixture(repeatReporter = true)
let repeated = prepareComputedEnvelope(repeatedSource, cap(repeatedSource, 1)).value
assert repeated.computedEnvelopeInfo.value.reporters == 1, "actual reporter identity deduplicated before policy"
expect(repeated.computedEnvelopeReporterAt(ComputedReporterIndex(1)),
    ComputedEnvelopeError.InvalidIndex)
assert repeated.computedEnvelopeGuarantee.value.credentialCount == 2, "distinct valid credential indices are preserved"
assert uint16(repeated.computedEnvelopeGuarantee.value.credentials[0].validator) == 1
assert uint16(repeated.computedEnvelopeGuarantee.value.credentials[1].validator) == 2
assert repeated.computedEnvelopeBytes.value == independentWire(repeatedSource)
assert array[32, byte](repeated.computedEnvelopeReporterAt(ComputedReporterIndex(0)).value) == key("2ebbc3db123aa602b343f36e3e16b89dc231e0310545a39ce8a7936734f8bf15")
let priorSource = envelopeFixture(prior = true)
let prior = prepareComputedEnvelope(priorSource, cap(priorSource)).value
assert prior.computedEnvelopeBytes.value == independentWire(priorSource)
assert uint16(prior.computedEnvelopeGuarantee.value.credentials[1].validator) == 8, "previous9 index survives current6 canonical output"
assert decodeGuarantee(prior.computedEnvelopeBytes.value, GuaranteeConfig(cores: CoreCount(3),
    validators: ValidatorCount(9), maxBytes: ByteLimit(100000))).error == GuaranteeError.None
# Independent returned copies cannot change bytes, report ownership, credentials, metadata or reporter keys.
var mutableWire = done.computedEnvelopeBytes.value
mutableWire[0] = mutableWire[0] xor 1
var mutableGuarantee = done.computedEnvelopeGuarantee.value
mutableGuarantee.report = default(OwnedReport)
mutableGuarantee.credentials[0].signature = default(GuaranteeSignature)
mutableGuarantee.slot = GuaranteeSlot(99)
var mutableInfo = done.computedEnvelopeInfo.value
mutableInfo.reporters = 0
var mutableKey = done.computedEnvelopeReporterAt(ComputedReporterIndex(0)).value
mutableKey = default(StateEdKey)
assert done.computedEnvelopeBytes.value == expected
assert uint32(done.computedEnvelopeGuarantee.value.slot) == 2
assert ownedReportInfo(done.computedEnvelopeGuarantee.value.report).error == OwnershipError.None
assert done.computedEnvelopeInfo.value.reporters == 2
reset(1)
expect(prepareComputedEnvelope(source, limits), ComputedEnvelopeError.None)
expect(prepareComputedEnvelope(priorSource, cap(priorSource)), ComputedEnvelopeError.None)
expect(prepareComputedEnvelope(source, shortSet), ComputedEnvelopeError.LimitExceeded)
discard done.computedEnvelopeBytes.value
assert hashes() == 0, "materialization and reporter extraction perform no hashes"
reset(0)
proc detached(): ComputedGuaranteeEnvelope =
  ## Retain source credentials, independent report, canonical wire and reporter set after caller owners retire.
  let source = envelopeFixture(prior = true)
  prepareComputedEnvelope(source, cap(source)).value
let retained = detached()
assert uint16(retained.computedEnvelopeGuarantee.value.credentials[1].validator) == 8
proc cycle(source, repeated: CredentialedComputedReport, limits, repeatedLimits,
    short: ComputedEnvelopeLimits) =
  ## Release captured reports/wires, fixed reporter storage, returned copies and late reporter-policy refusals.
  let value = prepareComputedEnvelope(source, limits).value
  discard value.computedEnvelopeBytes.value
  discard value.computedEnvelopeGuarantee.value
  discard value.computedEnvelopeReporterAt(ComputedReporterIndex(0)).value
  discard prepareComputedEnvelope(repeated, repeatedLimits).value
  expect(prepareComputedEnvelope(source, short), ComputedEnvelopeError.LimitExceeded)
cycle(source, repeatedSource, limits, cap(repeatedSource, 1), shortSet)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(source, repeatedSource, limits, cap(repeatedSource, 1), shortSet)
let occupied = getOccupiedMem()
assert before == occupied, "computed envelope ARC release"
recordArcRelease("pvm_computed_envelope", 1000, before, occupied)
echo "PVM computed envelope passed"
echo "ARC_RELEASE cycles=1000 unchanged"
