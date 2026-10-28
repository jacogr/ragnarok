# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_credentials_arc_release"}

## Real source-bound credentials, canonicality/preflight, retained message identity and immutable ARC lifetime.

import std/assertions
import std/syncio
import ../../../src/state/computed_credentials as state_computed_credentials
import ../../../src/state/computed_guarantors as state_computed_guarantors
import ../../../src/state/computed_roster as state_computed_roster
import ../../../src/state/computed_transition as state_computed_transition
import ../../../src/state/computed_profile as state_computed_profile
import ../../../src/state/computed_lookup as state_computed_lookup
import ../../../src/state/computed_recent as state_computed_recent
import ../../../src/state/computed_state as state_computed_state
import ../../../src/state/computed_links as state_computed_links
import ../../../src/state/computed_guarantee as state_computed_guarantee
import ../../../src/state/computed_report as state_computed_report
import ../../../src/state/store as state_store
import ../../../src/codec/guarantees as codec_guarantees
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/crypto/primitives as crypto_primitives
import ../../../src/crypto/guarantee as crypto_guarantee
import ../../support/pvm_computed_credentials
import ../../support/testing_arc_evidence

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse new Blake2b hashing after original computation, planning and test signatures complete.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count actual report rehash attempts rather than simulating crypto success.
proc expect[T](outcome: ComputedCredentialResult[T], reason: ComputedCredentialError, label = "") =
  ## Compare precise successful/refused alternatives before extraction.
  assert outcome.error == reason, "computed credential " & label & " reason: " & $outcome.error &
      " expected: " & $reason
proc assignment[T](outcome: ComputedCredentialResult[T], reason: ComputedGuarantorError) =
  ## Inspect a nested assignment cause only in its selected failure alternative.
  expect(outcome, ComputedCredentialError.AssignmentFailure)
  assert outcome.assignmentError == reason, "original selected assignment refusal"
let source = credentialFixture()
let message = credentialMessage(source)
let transcript = source.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileSource.value.computedLookupSource.value.computedRecentSource.value.computedStateSource.value.computedLinkSource.value
let wire = transcript.computedGuaranteeReport.value.computedReportBytes.value
assert message == array[45, byte](guaranteeMessage(wire).value), "canonical complete report independently hashed by maintained composition"
for i, octet in "jam_guarantee": assert message[i] == byte(
    octet) # Exact ASCII token with no wrapper or terminator.
var records = signedCredentials(source, GuaranteeSlot(2), [1'u16, 2], message)
let two = records
let three = signedCredentials(source, GuaranteeSlot(2), [1'u16, 2, 5], message)
let done = verifyComputedCredentials(source, GuaranteeSlot(2), records).value
assert done.computedCredentialInfo.value.credentials == 2
assert uint32(done.computedCredentialInfo.value.slot) == 2
assert uint16(done.computedCredentialAt(ComputedCredentialIndex(1)).value.validator) == 2
expect(verifyComputedCredentials(source, GuaranteeSlot(2), three), ComputedCredentialError.None, "three signers")
# A slot inside the same rotation changes metadata but never the signed message.
expect(verifyComputedCredentials(source, GuaranteeSlot(1), two), ComputedCredentialError.None,
    "same rotation")
let reverse = [two[1], two[0]]
let duplicate = [two[0], two[0]]
expect(verifyComputedCredentials(source, GuaranteeSlot(2), reverse),
    ComputedCredentialError.NonCanonical)
expect(verifyComputedCredentials(source, GuaranteeSlot(2), duplicate),
    ComputedCredentialError.NonCanonical)
for count in [0, 1, 4]:
  expect(verifyComputedCredentials(source, GuaranteeSlot(2), newSeq[GuaranteeCredential](count)),
      ComputedCredentialError.InvalidCount)
assignment(verifyComputedCredentials(source, GuaranteeSlot(3), two),
    ComputedGuarantorError.InvalidSlot)
var badIndex = two
badIndex[1].validator = GuarantorIndex(high(uint16))
assignment(verifyComputedCredentials(source, GuaranteeSlot(2), badIndex),
    ComputedGuarantorError.InvalidIndex)
var damaged = three
var signature = array[64, byte](damaged[2].signature)
signature[0] = signature[0] xor 1
damaged[2].signature = GuaranteeSignature(signature)
expect(verifyComputedCredentials(source, GuaranteeSlot(2), damaged),
    ComputedCredentialError.InvalidSignature)
var firstBad = two
signature = array[64, byte](firstBad[0].signature)
signature[63] = signature[63] xor 1
firstBad[0].signature = GuaranteeSignature(signature)
expect(verifyComputedCredentials(source, GuaranteeSlot(2), firstBad),
    ComputedCredentialError.InvalidSignature)
var lateWrongCore = firstBad
lateWrongCore[1].validator = GuarantorIndex(3)
assignment(verifyComputedCredentials(source, GuaranteeSlot(2), lateWrongCore),
    ComputedGuarantorError.WrongAssignment)
# Real signatures on altered domain/hash bytes must fail even when signer indices and assignments remain valid.
var foreign = message
foreign[0] = foreign[0] xor 1
let wrongDomain = signedCredentials(source, GuaranteeSlot(2), [1'u16, 2], foreign)
expect(verifyComputedCredentials(source, GuaranteeSlot(2), wrongDomain),
    ComputedCredentialError.InvalidSignature)
foreign = message
foreign[44] = foreign[44] xor 1
let wrongHash = signedCredentials(source, GuaranteeSlot(2), [1'u16, 2], foreign)
expect(verifyComputedCredentials(source, GuaranteeSlot(2), wrongHash),
    ComputedCredentialError.InvalidSignature)
let otherSource = credentialFixture(core = 1)
let otherMessage = credentialMessage(otherSource)
assert otherMessage != message, "different original computed report changes its actual message"
let otherReport = signedCredentials(source, GuaranteeSlot(2), [1'u16, 2], otherMessage)
expect(verifyComputedCredentials(source, GuaranteeSlot(2), otherReport),
    ComputedCredentialError.InvalidSignature)
# Previous9 selected keys remain valid even though these credential positions do not exist in current6.
let crossing = credentialFixture(shrink = true, core = 1)
let prior = signedCredentials(crossing, GuaranteeSlot(8), [7'u16, 8], credentialMessage(crossing))
let priorDone = verifyComputedCredentials(crossing, GuaranteeSlot(8), prior).value
assert uint16(priorDone.computedCredentialAt(ComputedCredentialIndex(1)).value.validator) == 8
assignment(verifyComputedCredentials(crossing, GuaranteeSlot(7), prior),
    ComputedGuarantorError.InvalidSlot)
assignment(verifyComputedCredentials(crossing, GuaranteeSlot(12), prior),
    ComputedGuarantorError.InvalidIndex)
let excludedSource = credentialFixture(offender = true)
let excludedMessage = credentialMessage(excludedSource)
let one = signedCredentials(excludedSource, GuaranteeSlot(2), [1'u16], excludedMessage)
let excluded = [one[0], GuaranteeCredential(validator: GuarantorIndex(5),
    signature: credentialSignature(16, excludedMessage))]
assignment(verifyComputedCredentials(excludedSource, GuaranteeSlot(2), excluded),
    ComputedGuarantorError.IneligibleValidator)
expect(verifyComputedCredentials(default(ComputedGuarantors), GuaranteeSlot(2), two),
    ComputedCredentialError.InvalidSource)
expect(default(ComputedCredentialResult[CredentialedComputedReport]),
    ComputedCredentialError.Uninitialized)
expect(default(CredentialedComputedReport).computedCredentialSource,
    ComputedCredentialError.Uninitialized)
expect(default(CredentialedComputedReport).computedCredentialInfo,
    ComputedCredentialError.Uninitialized)
expect(default(CredentialedComputedReport).computedCredentialAt(ComputedCredentialIndex(0)),
    ComputedCredentialError.Uninitialized)
expect(done.computedCredentialAt(ComputedCredentialIndex(2)), ComputedCredentialError.InvalidIndex)
expect(done.computedCredentialAt(ComputedCredentialIndex(high(uint64))),
    ComputedCredentialError.InvalidIndex)
# Every caller-owned record and fixed query copy can change without replacing retained successful provenance.
records[0].signature = default(GuaranteeSignature)
var copied = done.computedCredentialAt(ComputedCredentialIndex(0)).value
copied.validator = GuarantorIndex(0)
var info = done.computedCredentialInfo.value
info.slot = GuaranteeSlot(99)
info.credentials = 3
assert uint16(done.computedCredentialAt(ComputedCredentialIndex(0)).value.validator) == 1
assert array[64, byte](done.computedCredentialAt(ComputedCredentialIndex(0)).value.signature) ==
    array[64, byte](two[0].signature)
assert uint32(done.computedCredentialInfo.value.slot) == 2 and
    done.computedCredentialInfo.value.credentials == 2
let original = source.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.state
assert sameStateSnapshot(done.computedCredentialSource.value.computedGuarantorSource.value.computedRosterSource.value.computedTransitionSource.value.computedProfileContext.value.state, original)
reset(1)
expect(verifyComputedCredentials(source, GuaranteeSlot(2), two), ComputedCredentialError.None, "hash-refusal control")
expect(verifyComputedCredentials(source, GuaranteeSlot(2), damaged),
    ComputedCredentialError.InvalidSignature)
assignment(verifyComputedCredentials(source, GuaranteeSlot(2), lateWrongCore),
    ComputedGuarantorError.WrongAssignment)
assert hashes() == 0, "credential verification never rehashes the retained original report"
reset(0)
proc detached(): CredentialedComputedReport =
  ## Preserve full original context and fixed credential bytes after all source/signing inputs retire.
  let source = credentialFixture(shrink = true, core = 1)
  let records = signedCredentials(source, GuaranteeSlot(8), [7'u16, 8], credentialMessage(source))
  verifyComputedCredentials(source, GuaranteeSlot(8), records).value
let retained = detached()
assert uint16(retained.computedCredentialAt(ComputedCredentialIndex(1)).value.validator) == 8
proc cycle(source: ComputedGuarantors, good, bad: openArray[GuaranteeCredential]) =
  ## Retire complete source-bound owners and a late cryptographic refusal without partial credential publication.
  let value = verifyComputedCredentials(source, GuaranteeSlot(2), good).value
  discard value.computedCredentialSource.value
  discard value.computedCredentialInfo.value
  discard value.computedCredentialAt(ComputedCredentialIndex(1)).value
  expect(verifyComputedCredentials(source, GuaranteeSlot(2), bad),
      ComputedCredentialError.InvalidSignature)
cycle(source, three, damaged)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(source, three, damaged)
let occupied = getOccupiedMem()
assert before == occupied, "computed credential ARC release"
recordArcRelease("pvm_computed_credentials", 1000, before, occupied)
echo "PVM computed credentials passed"
echo "ARC_RELEASE cycles=1000 unchanged"
