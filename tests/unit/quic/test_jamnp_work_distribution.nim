# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "jamnp_work_distribution_arc_release"}

## Genuine independent CE134 computation/signatures feed source-bound CE135 checks, fresh policy failures and deduplicated current/next recipients.
import std/[assertions, envvars, syncio]
import ../../../src/app/startup
import ../../../src/jamnp-s/[work_distribution, work_guarantee, work_signer, work_eligibility,
    work_sharing, sharing_wire]
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, guarantees, assurances, report_owned, owned, header, disputes]
import ../../../src/codec/work/package
import ../../../src/codec/state/[safrole, consensus, layout, trie, accounts, workqueues, history,
    disputes as state_disputes]
import ../../../src/state/[store, guarantee_credentials, guarantors]
import ../../../src/state/report/[policy, packages]
import ../../support/[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
    jamnp_topology_fixture, pvm_input_refinement, arc_evidence]
proc limits(): WorkDistributionLimits =
  ## Current source/GP parameters remain authoritative; all copy/recipient budgets are independently explicit.
  WorkDistributionLimits(eligibility: guaranteeLimits(), wireBytes: ByteLimit(20000),
      targets: ElementLimit(12))
proc shares(raw: WorkFixture): WorkSharingLimits =
  ## Independent guarantors execute the real package rather than signing a caller-selected report digest.
  WorkSharingLimits(packageBytes: ByteLimit(MaxBundleBytes), bundleBytes: ByteLimit(MaxBundleBytes),
      submission: raw.limits, execution: executionLimits(), report: workReportLimits(),
      eligibility: guaranteeLimits())
proc epochHead(fixture: GuaranteeFixture, atSlot: uint8 = 24): ChainView =
  ## A trusted complete fixture selects a slot in the next epoch and copies the genuine prior roster into C9.
  ## The snapshot remains test authority and grants no block admission certificate.
  let child = fixture.view.bestBlock.value
  let parent = fixture.view.parentOf(child.blockHash)
  assert parent.error == GenesisError.None
  var source = forkStateStore(child.stateSnapshot).value
  let previous = parent.value.lookup(chapterKey(StateChapter(8))).value.bytes
  let active = validatorEntry(ValidatorChapter.Active, topologyRecords(1, 6), topologyLimits(
      2).validators).value
  assert source.apply([StateWrite(kind: StateWriteKind.Put, key: active.key, value: active.value),
      StateWrite(kind: StateWriteKind.Put, key: chapterKey(StateChapter(9)), value: previous),
          StateWrite(kind: StateWriteKind.Put, key: chapterKey(StateChapter(11)),
      value: @[atSlot, 0'u8, 0, 0])]).error == StateStoreError.None
  var wire = newSeq[byte](child.header.headerInfo.value.consumed)
  assert child.header.encodeOwnedHeader(wire).error == HeaderError.None
  wire[96] = atSlot
  let saved = captureBlockSnapshot(wire, source.snapshot.value, child.chainParameters)
  assert saved.error == GenesisError.None
  let view = advanceView(genesisView(parent), saved)
  assert view.error == ViewAdvanceError.None
  view.value
proc verifyTargets(checked: CheckedWorkDistribution, a, b, c: StateEdKey) =
  ## Literal fixture identities make last-rotation union/dedup observable without reproducing the implementation's set builder.
  assert checked.distributionInfo.value.targets == 12
  let first = checked.distributionTarget(0).value
  assert array[32, byte](first.ed25519) == array[32, byte](topologyKey(20))
  assert array[32, byte](checked.distributionTarget(1).value.ed25519) == array[32, byte](a)
  assert array[32, byte](checked.distributionTarget(2).value.ed25519) == array[32, byte](b)
  assert array[32, byte](checked.distributionTarget(5).value.ed25519) == array[32, byte](c)
  for index in 0..<6:
    # Next-epoch fixture keys60..65 follow the six current identities in their original order.
    assert array[32, byte](checked.distributionTarget(6+index).value.ed25519) == array[32, byte](
        topologyKey(60+index))
  assert checked.distributionTarget(-1).error == WorkDistributionError.InvalidIndex
  assert checked.distributionTarget(12).error == WorkDistributionError.InvalidIndex
proc cycle(bytes: seq[byte], view: ChainView) =
  ## Repeated private source/credential/anchor/wire owners must all retire at this call boundary.
  let checked = qualifyWorkDistribution(bytes, view, StateTime(20), limits())
  assert checked.error == WorkDistributionError.None
  assert checked.value.distributionInfo.value.targets == 12
proc main() {.raises.} =
  ## Maintained signing uses three independent actual keys; every report was computed under its original complete execution map.
  let a = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT"), getEnv("RAGNAROK_TEST_KEY")).value
  let b = loadWorkSigner(getEnv("RAGNAROK_TEST_CERT_B"), getEnv("RAGNAROK_TEST_KEY_B")).value
  var diagnostic = ""
  assert ensureIdentity("distribution-c", diagnostic)
  let c = loadWorkSigner("distribution-c/cert.pem", "distribution-c/key.pem").value
  let keyA = a.signerIdentity.value
  let keyB = b.signerIdentity.value
  let keyC = c.signerIdentity.value
  let fixture = guaranteeFixture(keyA, keyB, keyC)
  let parent = fixture.view.parentOf(fixture.view.bestBlock.value.blockHash)
  assert parent.error == GenesisError.None
  let view = genesisView(parent)
  echo "distribution fixture ready"
  let raw = workFixture()
  let eligible = qualifyWorkGuarantee(fixture.transcript, fixture.original, fixture.execution, view,
      keyA, StateTime(20), guaranteeLimits())
  assert eligible.error == WorkEligibilityError.None
  let local = a.signWorkContribution(eligible.value).value
  let request = prepareWorkSharing(local, ByteLimit(20000)).value
  let receivedB = receiveSharedWork(request, view, keyB, keyA, StateTime(20), b, shares(raw))
  let receivedC = receiveSharedWork(request, view, keyC, keyA, StateTime(20), c, shares(raw))
  assert receivedB.error == WorkSharingError.None and receivedC.error == WorkSharingError.None
  let round = beginWorkGuarantee(local).value
  let pair = addWorkResponse(round, sharingTarget(local, 1).value, keyB,
      receivedB.value.sharingResponse.value).value
  let triple = addWorkResponse(pair, sharingTarget(local, 2).value, keyC,
      receivedC.value.sharingResponse.value).value
  let bytes = collectWorkGuarantee(triple, ByteLimit(20000)).value.guaranteePayload.value
  let two = collectWorkGuarantee(pair, ByteLimit(20000)).value.guaranteePayload.value
  echo "distribution credentials ready"
  let checked = qualifyWorkDistribution(bytes, view, StateTime(20), limits())
  assert checked.error == WorkDistributionError.None, "fresh CE135: " & $checked.error
  verifyTargets(checked.value, keyA, keyB, keyC)
  let facts = checked.value.distributionInfo.value
  assert array[32, byte](facts.head) == array[32, byte](parent.value.blockHash) and uint32(
      facts.observed) == 20 and uint32(facts.inclusion) == 21
  assert uint32(facts.lastSlot) == 27 and facts.credentials == 3 and facts.wireBytes == bytes.len
  assert array[32, byte](facts.root) == array[32, byte](parent.value.stateRoot)
  assert checked.value.distributionGuarantee.value.credentialCount == 3
  var copy = checked.value.distributionPayload.value
  copy[0] = copy[0] xor 1
  assert checked.value.distributionPayload.value == bytes
  echo "distribution recipients checked"
  let refreshed = qualifyWorkDistribution(two, fixture.view, StateTime(21), limits())
  assert refreshed.error == WorkDistributionError.None, "later complete source: " & $refreshed.error
  assert array[32, byte](refreshed.value.distributionInfo.value.head) != array[32, byte](facts.head)
  assert refreshed.value.distributionGuarantee.value.credentialCount == 2
  var changedRoster = topologyRecords(0, 6)
  changedRoster[1].ed25519 = keyA
  changedRoster[2].ed25519 = keyB
  let replacedRoster = validatorEntry(ValidatorChapter.Active, changedRoster, topologyLimits(
      2).validators).value
  let changedCohort = qualifyWorkDistribution(bytes, fixture.replacedHead(replacedRoster),
      StateTime(21), limits())
  assert changedCohort.error == WorkDistributionError.CredentialFailure
  assert changedCohort.credentialError.error == GuaranteeCredentialError.InvalidSignature
  var pending = topologyRecords(1, 6)
  pending[0].ed25519 = keyA
  pending[1].ed25519 = keyB
  pending[2].ed25519 = keyC
  pending[3] = nullValidator()
  pending[4].ed25519 = topologyKey(20)
  let overlapped = safroleStateEntry(SafroleState(pending: pending, schedule: keySchedule(newSeq[
      StateBsKey](12))), topologyLimits(2)).value
  let union = qualifyWorkDistribution(two, fixture.replacedHead(overlapped), StateTime(21), limits())
  assert union.error == WorkDistributionError.None
  assert union.value.distributionInfo.value.targets == 7
  assert array[32, byte](union.value.distributionTarget(6).value.ed25519) == array[32, byte](
      topologyKey(65))
  assert array[128, byte](union.value.distributionTarget(1).value.metadata)[16] ==
      55 # Current metadata wins over a duplicate next-roster identity.
  assert array[32, byte](union.value.distributionInfo.value.root) != array[32, byte](
      refreshed.value.distributionInfo.value.root)
  let next = qualifyWorkDistribution(bytes, epochHead(fixture), StateTime(24), limits())
  assert next.error == WorkDistributionError.None, "previous-epoch credentials: " & $next.error
  assert next.value.distributionInfo.value.targets == 6
  assert array[32, byte](next.value.distributionTarget(0).value.ed25519) == array[32, byte](
      topologyKey(60))
  assert next.value.distributionGuarantee.value.credentialCount == 3
  let last = qualifyWorkDistribution(bytes, epochHead(fixture, 27), StateTime(27), limits())
  assert last.error == WorkDistributionError.None, "last current credential slot: " & $last.error
  assert uint32(last.value.distributionInfo.value.inclusion) == 28
  assert not last.value.distributionInfo.value.withinCredentialWindow
  let expired = qualifyWorkDistribution(bytes, epochHead(fixture, 28), StateTime(28), limits())
  assert expired.error == WorkDistributionError.CredentialFailure
  assert expired.credentialError.error == GuaranteeCredentialError.AssignmentFailure
  assert expired.credentialError.assignmentError == GuarantorError.InvalidSlot
  echo "distribution epochs checked"
  assert qualifyWorkDistribution(bytes, view, StateTime(19), limits()).error ==
      WorkDistributionError.InvalidSlot
  assert qualifyWorkDistribution(bytes, view, StateTime(24), limits()).error ==
      WorkDistributionError.UncertainEpoch
  var altered = bytes
  altered.add(0)
  assert qualifyWorkDistribution(altered, view, StateTime(20), limits()).error ==
      WorkDistributionError.TrailingBytes
  altered = bytes
  altered[altered.high] = altered[altered.high] xor 1
  let badSignature = qualifyWorkDistribution(altered, view, StateTime(20), limits())
  assert badSignature.error == WorkDistributionError.CredentialFailure
  assert badSignature.credentialError.error == GuaranteeCredentialError.InvalidSignature
  var record = checked.value.distributionGuarantee.value
  record.slot = GuaranteeSlot(21)
  let config = GuaranteeConfig(cores: CoreCount(2), validators: ValidatorCount(6),
      maxBytes: ByteLimit(20000))
  let future = qualifyWorkDistribution(encodeGuaranteeValue(record, config).value, view, StateTime(
      20), limits())
  assert future.error == WorkDistributionError.CredentialFailure
  assert future.credentialError.error == GuaranteeCredentialError.AssignmentFailure
  assert future.credentialError.assignmentError == GuarantorError.InvalidSlot
  record.slot = GuaranteeSlot(12)
  let stale = qualifyWorkDistribution(encodeGuaranteeValue(record, config).value, view, StateTime(
      20), limits())
  assert stale.error == WorkDistributionError.CredentialFailure
  assert stale.credentialError.assignmentError == GuarantorError.InvalidSlot
  var small = limits()
  small.targets = ElementLimit(11)
  assert qualifyWorkDistribution(bytes, view, StateTime(20), small).error ==
      WorkDistributionError.LimitExceeded
  small = limits()
  small.wireBytes = ByteLimit(uint64(bytes.len-1))
  assert qualifyWorkDistribution(bytes, view, StateTime(20), small).error ==
      WorkDistributionError.LimitExceeded
  small = limits()
  small.eligibility.duty.chapterBytes = ByteLimit(3)
  assert qualifyWorkDistribution(bytes, view, StateTime(20), small).error ==
      WorkDistributionError.LimitExceeded
  small = limits()
  small.eligibility.policy.reportGas = ReportGasLimit(10000001)
  assert qualifyWorkDistribution(bytes, view, StateTime(20), small).error ==
      WorkDistributionError.InvalidPolicy
  echo "distribution refusals checked"
  let report = checked.value.distributionGuarantee.value.report
  let service = report.ownedReportDigest(0).value.service
  let wrongCode = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(
      ServiceMetadataBytes)).value
  let policyFailure = qualifyWorkDistribution(two, fixture.replacedHead(wrongCode), StateTime(21),
      limits())
  assert policyFailure.error == WorkDistributionError.PolicyFailure
  assert policyFailure.policyError == ReportPolicyError.WrongCodeHash
  var accumulated = newSeq[AccumulatedRow](12)
  accumulated[0] = @[report.ownedReportInfo.value.header.packageHash]
  let duplicate = accumulatedStateEntry(accumulated, guaranteeLimits().pipeline.queues).value
  let pipeline = qualifyWorkDistribution(two, fixture.replacedHead(duplicate), StateTime(21),
      limits())
  assert pipeline.error == WorkDistributionError.PipelineFailure
  assert pipeline.pipelineError == ReportPackageError.DuplicatePackage
  var blocked = default(DisputeState)
  blocked.offenders = @[OffenderKey(array[32, byte](keyA))]
  let disputed = disputeStateEntry(blocked, DisputeStateConfig(perSet: ElementLimit(128),
      totalItems: ElementLimit(128), maxBytes: ByteLimit(10000))).value
  let offender = qualifyWorkDistribution(two, fixture.replacedHead(disputed), StateTime(21), limits())
  assert offender.error == WorkDistributionError.CredentialFailure
  assert offender.credentialError.error == GuaranteeCredentialError.InvalidSignature
  let noHistory = historyStateEntry(HistoryState(blocks: @[]), guaranteeLimits().anchors.history).value
  let missingAnchors = qualifyWorkDistribution(two, fixture.replacedHead(noHistory), StateTime(21),
      limits())
  assert missingAnchors.error == WorkDistributionError.AnchorFailure
  let malformedEntropy = StateEntry(key: chapterKey(StateChapter(6)), value: @[20'u8])
  let entropyFailure = qualifyWorkDistribution(two, fixture.replacedHead(malformedEntropy),
      StateTime(21), limits())
  assert entropyFailure.error == WorkDistributionError.ComponentFailure
  assert entropyFailure.chapter == StateChapter(6)
  echo "distribution sources checked"
  for length in 0..<bytes.len:
    # No standalone prefix can acquire complete credential/recipient evidence.
    let prefix = bytes.toOpenArray(0, length-1)
    let refused = qualifyWorkDistribution(prefix, view, StateTime(20), limits())
    assert refused.error != WorkDistributionError.None
  cycle(two, view)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(two, view)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("jamnp_work_distribution", 1000, before, after)
  echo "JAMNP-S work distribution qualification passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try:
  main()
except:
  quit 2 # Setup failures cannot substitute for actual report credentials and complete-state checks.
