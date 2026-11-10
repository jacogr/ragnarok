# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_work_guarantee_arc_release"}

## Three actual TLS identities independently compute/sign one original shared bundle; only checked unique responses assemble canonical guarantees.

import std/[assertions, envvars, syncio]
import ../../../src/app/startup
import ../../../src/jamnp-s/[work_guarantee, work_signer, work_duty, work_eligibility,
  work_sharing, sharing_wire]
import ../../../src/codec/[bounded, guarantees, assurances]
import ../../../src/codec/state/[safrole, layout, disputes]
from ../../../src/codec/header import EpochSlots
import ../../../src/state/[guarantee_credentials, guarantors]
import ../../../src/chain/parameters
import ../../../src/chain/[provider, genesis]
import ../../../src/state/store
import ../../../src/codec/work/package
import ../../../src/state/computed/guarantee
import ../../../src/crypto/primitives
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
  pvm_input_refinement, arc_evidence]

proc policy(raw: WorkFixture): WorkSharingLimits =
  ## Actual source consensus limits remain independent from explicit local execution and byte budgets.
  WorkSharingLimits(packageBytes: ByteLimit(MaxBundleBytes), bundleBytes: ByteLimit(MaxBundleBytes),
    submission: raw.limits, execution: executionLimits(), report: workReportLimits(),
        eligibility: guaranteeLimits(), retention: guarantorLimits())

proc refused(outcome: WorkGuaranteeResult[WorkGuaranteeRound], reason: WorkGuaranteeError) =
  ## A rejected reply never extracts an accepted prefix or changes the caller's original immutable round.
  assert outcome.error == reason

proc signed(fixture: GuaranteeFixture, signer: WorkSigner, identity: StateEdKey,
    atSlot = 21'u32): SignedWorkContribution =
  ## Only genuine original/fresh-source qualification and the actual matching private TLS key can supply a local credential.
  let eligible = qualifyWorkGuarantee(fixture.transcript, fixture.original, fixture.execution,
    fixture.view, identity, StateTime(atSlot), guaranteeLimits())
  assert eligible.error == WorkEligibilityError.None
  let signedResult = signer.signWorkContribution(eligible.value, guarantorLimits())
  assert signedResult.error == WorkSignerError.None
  signedResult.value

proc checkedPayload(collected: CollectedWorkGuarantee, expectedCount: int): seq[byte] =
  ## Independently decode standalone GP bytes and verify strict original-index ordering after reverse arrival.
  let output = collected.guaranteePayload
  assert output.error == WorkGuaranteeError.None
  let config = GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      maxBytes: ByteLimit(20000))
  let parsed = decodeGuarantee(output.value, config)
  assert parsed.error == GuaranteeError.None
  assert parsed.value.consumed == output.value.len
  let guarantee = parsed.value.value
  assert uint32(guarantee.slot) == 21 and guarantee.credentialCount == expectedCount
  assert uint16(guarantee.credentials[0].validator) == 1
  if expectedCount == 2:
    assert uint16(guarantee.credentials[1].validator) == 5
  else:
    assert uint16(guarantee.credentials[1].validator) == 2
    assert uint16(guarantee.credentials[2].validator) == 5
  output.value

proc cycle(local: SignedWorkContribution, second, third: WorkShareTarget,
    secondKey, thirdKey: StateEdKey, secondReply, thirdReply: array[96, byte]) =
  ## Success and late refusal release every immutable intermediate round and complete encoded owner.
  let initial = beginWorkGuarantee(local).value
  let pair = addWorkResponse(initial, third, thirdKey, thirdReply)
  assert pair.error == WorkGuaranteeError.None
  assert initial.credentialCount == 1 and pair.value.credentialCount == 2
  let two = collectWorkGuarantee(pair.value, ByteLimit(20000))
  assert two.error == WorkGuaranteeError.None
  discard checkedPayload(two.value, 2)
  let full = addWorkResponse(pair.value, second, secondKey, secondReply)
  assert full.error == WorkGuaranteeError.None
  assert pair.value.credentialCount == 2 and full.value.credentialCount == 3
  let three = collectWorkGuarantee(full.value, ByteLimit(20000))
  assert three.error == WorkGuaranteeError.None
  let bytes = checkedPayload(three.value, 3)
  let tiny = collectWorkGuarantee(full.value, ByteLimit(uint64(bytes.len-1)))
  assert tiny.error == WorkGuaranteeError.CodecFailure
  assert tiny.codecError == GuaranteeError.LimitExceeded
  refused(addWorkResponse(full.value, second, secondKey, secondReply), WorkGuaranteeError.Duplicate)

proc verifyRepeated(fixture: GuaranteeFixture, value: Guarantee, reporters: int) =
  ## The ordinary GP verifier proves genuine repeated-key credentials, using actual complete roster/entropy and distinct original indices.
  let source = fixture.view.bestBlock.value.stateSnapshot
  let parameters = fixture.view.bestBlock.value.chainParameters
  let roster = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
      maxBytes: ByteLimit(10000))
  let active = decodeStateValidators(source.lookup(chapterKey(StateChapter(8))).value.bytes,
      roster).value.value
  let previous = decodeStateValidators(source.lookup(chapterKey(StateChapter(9))).value.bytes,
      roster).value.value
  let entropy = decodeStateEntropy(source.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value
  let config = GuaranteeCredentialConfig(assignments: GuarantorConfig(roster: roster,
    epochSlots: EpochSlots(parameters.get(epochPeriod)), rotationSlots: GuarantorRotationSlots(
        parameters.get(rotationPeriod)), offenders: ElementLimit(128)),
    maxBytes: ByteLimit(20000), reporters: ElementLimit(6))
  let verified = verifyGuaranteeCredentials([value], active, previous, entropy, StateTime(22), [], config)
  assert verified.error == GuaranteeCredentialError.None, "ordinary GP repeated-key credentials"
  assert verified.value.verifiedReporterCount.value == reporters, "reporters count keys independently of original credential indices"

proc repeatedKeys(a, b: WorkSigner) =
  ## A key shared by another core must not hide its valid local positions on this core; signature reuse follows the pinned GP transcript.
  let aKey = a.signerIdentity.value
  let bKey = b.signerIdentity.value
  let otherCore = StateValidator(ed25519: aKey)
  let fixture = guaranteeFixture(aKey, aKey, bKey, otherCore)
  let local = signed(fixture, a, aKey)
  assert uint16(local.contributionDuty.value.validatorIndex) == 1, "requested core selects the eligible local position"
  var direct = default(array[3, GuaranteeCredential])
  direct[0] = local.contributionCredential.value
  direct[1] = direct[0]
  direct[1].validator = GuarantorIndex(2)
  let witness = Guarantee(report: local.contributionReport.value, slot: GuaranteeSlot(21),
      credentials: direct, credentialCount: 2)
  verifyRepeated(fixture, witness, 1) # This independent positive control passes before assembly is changed.
  let initial = beginWorkGuarantee(local).value
  assert initial.credentialCount == 2, "both original local positions must contribute without a self request"
  assert sharingTarget(local, 0).error == WorkGuaranteeError.InvalidTarget
  assert sharingTarget(local, 1).error == WorkGuaranteeError.InvalidTarget
  let target = sharingTarget(local, 2).value
  let raw = workFixture()
  let response = receiveSharedWork(prepareWorkSharing(local, ByteLimit(20000)).value, fixture.view,
    bKey, aKey, StateTime(21), b, policy(raw))
  assert response.error == WorkSharingError.None
  let complete = addWorkResponse(initial, target, bKey, response.value.sharingResponse.value).value
  assert complete.credentialCount == 3
  let bytes = collectWorkGuarantee(complete, ByteLimit(20000)).value.checkedPayload(3)
  let wire = GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      maxBytes: ByteLimit(20000))
  verifyRepeated(fixture, decodeGuarantee(bytes, wire).value.value, 2)
  let all = guaranteeFixture(aKey, aKey, aKey, otherCore)
  let allLocal = signed(all, a, aKey)
  let allRound = beginWorkGuarantee(allLocal).value
  assert allRound.credentialCount == 3, "three original local positions need no remote signer"
  for position in 0..<3:
    assert sharingTarget(allLocal, position).error == WorkGuaranteeError.InvalidTarget
  verifyRepeated(all, decodeGuarantee(collectWorkGuarantee(allRound, ByteLimit(
      20000)).value.checkedPayload(3), wire).value.value, 1)
  let remote = guaranteeFixture(aKey, bKey, bKey)
  let origin = signed(remote, a, aKey)
  let offered = prepareWorkSharing(origin, ByteLimit(20000)).value
  let returned = receiveSharedWork(offered, remote.view, bKey, aKey, StateTime(21), b, policy(raw))
  assert returned.error == WorkSharingError.None
  let remoteTarget = sharingTarget(origin, 1).value
  let accepted = addWorkResponse(beginWorkGuarantee(origin).value, remoteTarget, bKey,
      returned.value.sharingResponse.value)
  assert accepted.error == WorkGuaranteeError.None and accepted.value.credentialCount == 3, "one authenticated remote response covers its two original positions"
  verifyRepeated(remote, decodeGuarantee(collectWorkGuarantee(accepted.value, ByteLimit(
      20000)).value.checkedPayload(3), wire).value.value, 2)

proc main() {.raises.} =
  ## Generate only test-owned third credentials; original provider identities and pinned crypto implementations remain unchanged.
  let a = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY"))
  let b = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B"))
  var diagnostic = ""
  assert ensureIdentity("assembly-peer-c", diagnostic)
  let c = loadWorkSigner("assembly-peer-c/cert.pem", "assembly-peer-c/key.pem")
  assert a.error == WorkSignerError.None and b.error == WorkSignerError.None and c.error ==
      WorkSignerError.None
  let aKey = a.value.signerIdentity.value
  let bKey = b.value.signerIdentity.value
  let cKey = c.value.signerIdentity.value
  repeatedKeys(a.value, b.value)
  let fixture = guaranteeFixture(aKey, bKey, cKey)
  let local = signed(fixture, a.value, aKey)
  let targetB = sharingTarget(local, 1)
  let targetC = sharingTarget(local, 2)
  assert targetB.error == WorkGuaranteeError.None and targetC.error == WorkGuaranteeError.None
  assert uint16(targetB.value.participant.index) == 2
  assert uint16(targetC.value.participant.index) == 5
  let self = sharingTarget(local, 0)
  let absent = sharingTarget(local, 3)
  let empty = sharingTarget(default(SignedWorkContribution), 0)
  assert self.error == WorkGuaranteeError.InvalidTarget
  assert absent.error == WorkGuaranteeError.InvalidTarget
  assert empty.error == WorkGuaranteeError.InvalidSource
  assert not default(WorkShareTarget).valid
  let raw = workFixture()
  let prepared = prepareWorkSharing(local, ByteLimit(MaxBundleBytes))
  assert prepared.error == WorkSharingError.None
  let denied = prepareWorkSharing(local, ByteLimit(1))
  let uninitialized = prepareWorkSharing(default(SignedWorkContribution), ByteLimit(MaxBundleBytes))
  assert denied.error == WorkSharingError.LimitExceeded
  assert uninitialized.error == WorkSharingError.InvalidSource
  var expectedFirst = @[raw.first[0], raw.first[1], 6'u8, 0]
  for index in 2..<raw.first.len: expectedFirst.add(raw.first[index])
  var expectedBundle = fixture.package
  for octet in raw.extrinsics: expectedBundle.add(octet)
  for octet in raw.segments: expectedBundle.add(octet)
  for octet in raw.proofs: expectedBundle.add(octet)
  assert prepared.value.firstMessage == expectedFirst
  assert prepared.value.bundleMessage == expectedBundle
  # Each receiver performs actual independent authorization/refinement/report/signing using the exact prepared whole bundle.
  let peerB = receiveSharedWork(prepared.value, fixture.view, bKey, aKey, StateTime(21), b.value,
      policy(raw))
  let peerC = receiveSharedWork(prepared.value, fixture.view, cKey, aKey, StateTime(21), c.value,
      policy(raw))
  assert peerB.error == WorkSharingError.None and peerC.error == WorkSharingError.None
  let replyB = peerB.value.sharingResponse.value
  let replyC = peerC.value.sharingResponse.value
  let initial = beginWorkGuarantee(local).value
  assert initial.credentialCount == 1 and default(WorkGuaranteeRound).credentialCount == 0
  let insufficient = collectWorkGuarantee(initial, ByteLimit(20000))
  assert insufficient.error == WorkGuaranteeError.InsufficientCredentials
  refused(addWorkResponse(default(WorkGuaranteeRound), targetB.value, bKey, replyB),
      WorkGuaranteeError.InvalidSource)
  refused(addWorkResponse(initial, default(WorkShareTarget), bKey, replyB),
      WorkGuaranteeError.InvalidTarget)
  refused(addWorkResponse(initial, targetB.value, cKey, replyB), WorkGuaranteeError.InvalidPeer)
  refused(addWorkResponse(initial, targetB.value, bKey, replyB.toOpenArray(0, 94)),
      WorkGuaranteeError.InvalidMessage)
  var suffix = newSeq[byte](97)
  for index in 0..<96: suffix[index] = replyB[index]
  refused(addWorkResponse(initial, targetB.value, bKey, suffix), WorkGuaranteeError.InvalidMessage)
  var hash = replyB
  hash[0] = hash[0] xor 1
  refused(addWorkResponse(initial, targetB.value, bKey, hash), WorkGuaranteeError.WrongReport)
  var signature = replyB
  signature[32] = signature[32] xor 1
  refused(addWorkResponse(initial, targetB.value, bKey, signature),
      WorkGuaranteeError.InvalidSignature)
  refused(addWorkResponse(initial, targetB.value, bKey, replyC),
      WorkGuaranteeError.InvalidSignature)
  let later = signed(fixture, a.value, aKey, 22)
  let otherSlot = sharingTarget(later, 1).value
  refused(addWorkResponse(initial, otherSlot, bKey, replyB), WorkGuaranteeError.InvalidTarget)
  let other = guaranteeFixture(aKey, bKey)
  let otherSigned = signed(other, a.value, aKey)
  let otherTarget = sharingTarget(otherSigned, 1).value
  refused(addWorkResponse(initial, otherTarget, bKey, replyB), WorkGuaranteeError.InvalidTarget)
  # Equal head hashes and report messages cannot substitute a different complete posterior cohort map.
  let canonicalHead = fixture.view.bestBlock.value
  let rosterConfig = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(6),
      maxBytes: ByteLimit(10000))
  let rosterBytes = canonicalHead.stateSnapshot.lookup(chapterKey(StateChapter(8))).value.bytes
  let roster = decodeStateValidators(rosterBytes, rosterConfig).value.value
  var records = newSeq[StateValidator](6)
  for index in 0..<6: records[index] = roster.validatorAt(StateValidatorIndex(index)).value
  records[2].ed25519 = cKey # The alternate source would assign the same responding identity to a different original ordinal.
  let entry = validatorEntry(ValidatorChapter.Active, records, rosterConfig).value
  var changedFixture = fixture
  changedFixture.view = fixture.replacedHead(entry)
  let changedLocal = signed(changedFixture, a.value, aKey)
  let changedTarget = sharingTarget(changedLocal, 1).value
  let originalMessage = array[45, byte](local.contributionTranscript.value.computedGuaranteeMessage.value)
  let changedMessage = array[45, byte](changedLocal.contributionTranscript.value.computedGuaranteeMessage.value)
  assert originalMessage == changedMessage
  let headBefore = array[32, byte](fixture.view.bestBlock.value.blockHash)
  let headAfter = array[32, byte](changedFixture.view.bestBlock.value.blockHash)
  assert headBefore == headAfter
  refused(addWorkResponse(initial, changedTarget, cKey, replyC), WorkGuaranteeError.InvalidTarget)
  assert initial.credentialCount == 1
  let pair = addWorkResponse(initial, targetC.value, cKey, replyC).value
  let collected = collectWorkGuarantee(pair, ByteLimit(20000)).value
  var changed = collected.guaranteePayload.value
  let beforeByte = changed[0]
  changed[0] = changed[0] xor 1
  assert collected.guaranteePayload.value[0] == beforeByte
  let defaultBytes = default(CollectedWorkGuarantee).guaranteePayload
  assert defaultBytes.error == WorkGuaranteeError.Uninitialized
  # The independent production GP credential verifier accepts both emitted thresholds against the actual canonical chapters.
  let actualState = fixture.view.bestBlock.value.stateSnapshot
  let active = decodeStateValidators(actualState.lookup(chapterKey(StateChapter(8))).value.bytes,
    rosterConfig).value.value
  let previous = decodeStateValidators(actualState.lookup(chapterKey(StateChapter(9))).value.bytes,
    rosterConfig).value.value
  let entropy = decodeStateEntropy(actualState.lookup(chapterKey(StateChapter(
      6))).value.bytes).value.value
  let disputes = decodeDisputeState(actualState.lookup(chapterKey(StateChapter(5))).value.bytes,
    DisputeStateConfig(perSet: ElementLimit(128), totalItems: ElementLimit(128),
        maxBytes: ByteLimit(10000)))
  assert disputes.error == DisputeStateError.None
  assert disputes.value.snapshot.disputeStateInfo.value.offenders == 0
  let parameters = fixture.view.bestBlock.value.chainParameters
  let credentialsPolicy = GuaranteeCredentialConfig(assignments: GuarantorConfig(
    roster: rosterConfig,
    epochSlots: EpochSlots(parameters.get(epochPeriod)),
    rotationSlots: GuarantorRotationSlots(parameters.get(rotationPeriod)), offenders: ElementLimit(128)),
    maxBytes: ByteLimit(20000), reporters: ElementLimit(6))
  let wirePolicy = GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      maxBytes: ByteLimit(20000))
  let completeRound = addWorkResponse(pair, targetB.value, bKey, replyB).value
  let completeGuarantee = collectWorkGuarantee(completeRound, ByteLimit(20000)).value
  for payload in [collected.guaranteePayload.value, completeGuarantee.guaranteePayload.value]:
    # No fixture-supplied assignment/key table or replacement report enters credential verification.
    let parsed = decodeGuarantee(payload, wirePolicy)
    assert parsed.error == GuaranteeError.None
    let verified = verifyGuaranteeCredentials([parsed.value.value], active, previous, entropy,
      StateTime(22), [], credentialsPolicy)
    assert verified.error == GuaranteeCredentialError.None
  cycle(local, targetB.value, targetC.value, bKey, cKey, replyB, replyC)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Repeated real signature verification, both thresholds, sorted encodings and late byte refusal must release every owner.
    cycle(local, targetB.value, targetC.value, bKey, cKey, replyB, replyC)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_work_guarantee", 1000, before, after)
  echo "JAMNP-S verified work guarantee assembly passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Setup exceptions cannot substitute for genuine peer computation or verified collection.
