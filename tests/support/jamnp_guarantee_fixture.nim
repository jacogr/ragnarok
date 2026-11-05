# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine package/body/PVM report execution uses an older complete map while fresh eligibility reads its actual child view.
import std/assertions
import ../../src/jamnp-s/[work_submission, work_report, work_anchors, work_duty, work_eligibility, work_signer]
import ../../src/chain/[provider, genesis, parameters]
import ../../src/codec/[bounded, header, guarantees, report_owned, owned, assurances]
import ../../src/codec/work/[package, report]
import ../../src/codec/state/[safrole, consensus, history, layout, availability, workqueues,
    accounts, trie]
import ../../src/state/[store, input_refinement, ancestor_context]
import ../../src/codec/state/authorization
import ../../src/state/report/[policy, packages]
import ../../src/state/computed/guarantee
import ../../src/crypto/[primitives, guarantee as crypto_guarantee]
import ./[jamnp_work_fixture, jamnp_work_report_fixture, jamnp_topology_fixture,
  pvm_input_refinement, pvm_import_inputs, pvm_import_vectors]

type
  GuaranteeFixture* = object ## Test-owned immutable inputs retain real execution/source ownership, not a fabricated eligibility or signature.
    original*: WorkSubmissionHeader
    package*: seq[byte]
    execution*: StateStoreSnapshot
    view*: ChainView
    transcript*: ComputedGuaranteeTranscript
    local*: StateEdKey
proc guaranteeLimits*(): WorkEligibilityLimits =
  ## Actual Tiny consensus geometry and gas are separate from finite local copy/decoder policies.
  result = WorkEligibilityLimits(
    anchors: WorkAnchorLimits(history: HistoryConfig(cores: CoreCount(2), blocks: ElementLimit(8),
      perBlock: ElementLimit(2), totalPackages: ElementLimit(16), peaks: ElementLimit(64),
          maxBytes: ByteLimit(4096)),
      ancestors: AncestorContextLimits(header: HeaderConfig(cores: CoreCount(2),
          authorValidators: ValidatorCount(6),
        epochSlots: EpochSlots(12), maxBytes: ByteLimit(4096)), headers: ElementLimit(8),
            maxBytes: ByteLimit(32768))),
    population: topologyLimits(2), duty: WorkDutyLimits(chapterBytes: ByteLimit(10000),
        disputeItems: ElementLimit(128)),
    policy: ReportPolicyConfig(pools: AuthorizationConfig(cores: CoreCount(2),
        maxHashes: ElementLimit(16), maxBytes: ByteLimit(4096)),
      accountBytes: ByteLimit(ServiceMetadataBytes), reportGas: ReportGasLimit(10000000),
          refinementGas: RefinementGasLimit(1000000000)),
    pipeline: ReportPackageConfig(availability: AvailabilityConfig(guarantee: GuaranteeConfig(
        cores: CoreCount(2),
      validators: ValidatorCount(6), maxBytes: ByteLimit(100000)), maxPresent: ElementLimit(2),
          maxBytes: ByteLimit(200000)),
      queues: WorkQueueConfig(epochSlots: EpochSlots(12), cores: CoreCount(2),
          perSlot: ElementLimit(8), totalItems: ElementLimit(32),
        perDependencies: ElementLimit(8), totalDependencies: ElementLimit(256),
            reportBytes: ByteLimit(100000), maxBytes: ByteLimit(1000000)),
      indexItems: ElementLimit(1024)), reportBytes: ByteLimit(40000))
proc peak(): HistorySuperPeak =
  ## One independent public accumulation-root value is reused by the fixture's actual recent-history entries.
  var raw = default(array[32, byte])
  raw[0] = 33
  HistorySuperPeak(raw)
proc record(source: BlockSnapshot, pending: bool, mappings: bool): HistoryBlock =
  ## Only the newest C3 state commitment is pending; older complete roots and exact full-header hashes are preserved.
  result = HistoryBlock(header: HistoryHeaderHash(array[32, byte](source.blockHash)),
      slot: HistorySlot(source.slot), superPeak: peak())
  if not pending: result.state = HistoryStateRoot(array[32, byte](source.stateRoot))
  if mappings: result.packages = @[ReportedPackage(package: inputKey(1), segment: SegmentRoot(
      bytes: ThreeRoot))]
proc captured(source: BlockSnapshot, state: StateStoreSnapshot,
    parameters: Parameters): BlockSnapshotResult =
  ## Reuse the exact sealed header while capturing its supplied trusted complete posterior fixture map.
  var wire = newSeq[byte](source.header.headerInfo.value.consumed)
  assert source.header.encodeOwnedHeader(wire).error == HeaderError.None
  captureBlockSnapshot(wire, state, parameters)
proc source(fixture: WorkFixture, local, peer: StateEdKey): BlockSnapshotResult =
  ## Populate all report-policy and pipeline chapters before binding the package anchor to this complete state root.
  let seed = fixture.workSnapshot(local, peer)
  let config = guaranteeLimits()
  var state = forkStateStore(seed.stateSnapshot).value
  var writes: seq[StateWrite] = @[]
  let recent = historyStateEntry(HistoryState(blocks: @[record(seed, true, true)]),
      config.anchors.history).value
  let assignments = availabilityStateEntry([absentAssignment(), absentAssignment()],
      config.pipeline.availability).value
  let ready = readyStateEntry(newSeq[ReadyRow](12), config.pipeline.queues).value
  let accumulated = accumulatedStateEntry(newSeq[AccumulatedRow](12), config.pipeline.queues).value
  for entry in [recent, assignments, ready, accumulated]:
    # A test-only complete parent includes exact empty pipeline encodings, never missing-state shortcuts.
    writes.add(StateWrite(kind: StateWriteKind.Put, key: entry.key, value: entry.value))
  for index in 0..<fixture.input.package.workPackageInfo.value.items:
    # Earlier execution fixtures do not advertise a live account code hash; report eligibility requires the actual matching metadata.
    let item = fixture.input.package.workItemAt(index).value.workItemInfo.value
    let entry = serviceMetadataEntry(item.service, ServiceMetadata(codeHash: item.codeHash),
        ByteLimit(ServiceMetadataBytes)).value
    writes.add(StateWrite(kind: StateWriteKind.Put, key: entry.key, value: entry.value))
  assert state.apply(writes).error == StateStoreError.None
  captured(seed, state.snapshot.value, seed.chainParameters)
proc anchoredPackage(original: OwnedWorkPackage, anchor: BlockSnapshot): seq[byte] =
  ## Re-encode every actual original item/commitment with the final context before authorization/body verification, never patch a completed report.
  let info = original.workPackageInfo.value
  var package = WorkPackage(host: info.host, codeHash: info.codeHash,
    context: RefinementContext(anchor: report.BlockHash(bytes: array[32, byte](anchor.blockHash)),
        anchorSlot: AnchorSlot(anchor.slot),
      stateRoot: report.StateRoot(bytes: array[32, byte](anchor.stateRoot)),
          accumulationRoot: AccumulationRoot(bytes: array[32, byte](peak())),
      lookupAnchor: report.BlockHash(bytes: array[32, byte](anchor.blockHash)),
          lookupSlot: LookupSlot(anchor.slot),
      lookupStateRoot: LookupStateRoot(bytes: array[32, byte](anchor.stateRoot))))
  package.authorization = newSeq[byte](info.authorizationBytes)
  package.configuration = newSeq[byte](info.configurationBytes)
  assert original.copyPackageBlob(PackageBlob.Authorization, package.authorization).error ==
      PackageError.None
  assert original.copyPackageBlob(PackageBlob.Configuration, package.configuration).error ==
      PackageError.None
  for index in 0..<info.items:
    # Preserve payloads and each tagged import/extrinsic in original order.
    let selected = original.workItemAt(index).value
    let fields = selected.workItemInfo.value
    var item = WorkItem(service: fields.service, codeHash: fields.codeHash,
      refineGas: fields.refineGas,
      accumulateGas: fields.accumulateGas, exports: fields.exports, payload: newSeq[byte](
          fields.payloadBytes))
    assert selected.copyItemPayload(item.payload).error == PackageError.None
    for ordinal in 0..<fields.imports: item.imports.add(selected.importAt(ordinal).value)
    for ordinal in 0..<fields.extrinsics: item.extrinsics.add(selected.extrinsicAt(ordinal).value)
    package.items.add(item)
  var wire = newSeq[byte](4096)
  let encoded = encodeWorkPackage(package, fullPackageConfig(ByteLimit(4096)), wire)
  assert encoded.error == PackageError.None
  wire.setLen(encoded.value)
  wire
proc child(parent: BlockSnapshotResult, local, peer: StateEdKey): BlockSnapshotResult =
  ## The actual child header commits the parent's complete root and advances the canonical clock; execution still retains the parent.
  var current = topologyRecords(0, 6)
  current[1].ed25519 = local
  if array[32, byte](peer) != default(array[32, byte]): current[2].ed25519 = peer
  let seed = topologyCaptured([topologyRecords(0, 6), current, topologyRecords(1, 6)], cores = 2,
      atSlot = 21, parent = parent)
  assert seed.error == GenesisError.None
  let recent = historyStateEntry(HistoryState(blocks: @[record(parent.value, false, true), record(
      seed.value, true, false)]), guaranteeLimits().anchors.history).value
  var state = forkStateStore(parent.value.stateSnapshot).value
  let time = timeEntry(StateTime(21))
  assert state.apply([StateWrite(kind: StateWriteKind.Put, key: recent.key, value: recent.value),
    StateWrite(kind: StateWriteKind.Put, key: time.key, value: time.value)]).error ==
        StateStoreError.None
  captured(seed.value, state.snapshot.value, parent.value.chainParameters)
proc guaranteeFixture*(local: StateEdKey, peer = default(StateEdKey)): GuaranteeFixture =
  ## Only genuine original-header authorization, complete imported inputs, PVM execution and availability composition yield the transcript.
  let fixture = workFixture()
  let parent = source(fixture, local, peer)
  assert parent.error == GenesisError.None, "guarantee parent"
  let wire = anchoredPackage(fixture.input.package, parent.value)
  let decoded = decodeWorkSubmission(WorkSubmissionKind.Bundle, fixture.first, wire,
      fullPackageConfig(ByteLimit(4096)))
  assert decoded.error == WorkSubmissionError.None, "guarantee header"
  let granted = authorizeWorkSubmission(decoded.value, parent.value.stateSnapshot,
      parent.value.chainParameters, fixture.limits)
  assert granted.error == WorkSubmissionError.None, "guarantee authorization: " & $granted.error
  let inputs = completeBundleSubmission(granted.value, fixture.extrinsics, fixture.segments,
      fixture.proofs, fixture.limits)
  assert inputs.error == WorkSubmissionError.None, "guarantee inputs: " & $inputs.error
  let executed = runInputRefinement(parent.value.stateSnapshot, inputs.value, CoreIndex(0),
      parent.value.chainParameters, executionLimits())
  assert executed.error == InputRefinementError.None, "guarantee execution: " & $executed.error
  let computed = prepareWorkReport(executed.value, ErasureShards(6), workReportLimits())
  assert computed.error == WorkReportError.None, "guarantee report: " & $computed.error
  let next = child(parent, local, peer)
  assert next.error == GenesisError.None, "guarantee child"
  let view = advanceView(genesisView(parent), next)
  assert view.error == ViewAdvanceError.None, "guarantee view: " & $view.error
  GuaranteeFixture(original: decoded.value, package: wire, execution: parent.value.stateSnapshot,
    view: view.value, transcript: computed.value, local: local)
proc qualify*(fixture: GuaranteeFixture, limits: WorkEligibilityLimits): WorkEligibilityResult[
    EligibleWorkGuarantee] =
  ## Keep all provenance inputs fixed while individual negative cases change only the relevant policy or observed identity.
  qualifyWorkGuarantee(fixture.transcript, fixture.original, fixture.execution, fixture.view,
    fixture.local, StateTime(21), limits)
proc guaranteeCycle*(fixture: GuaranteeFixture, signer: WorkSigner) =
  ## Successful source checks and a genuine private-key signature release all intermediate/retained owners on each cycle.
  let qualified = fixture.qualify(guaranteeLimits())
  assert qualified.error == WorkEligibilityError.None, "report eligibility: " & $qualified.error
  let contribution = signer.signWorkContribution(qualified.value)
  assert contribution.error == WorkSignerError.None, "report signing: " & $contribution.error
  let facts = contribution.value.contributionInfo.value
  let duty = contribution.value.contributionDuty.value
  assert duty.valid and duty.participantCount == 3
  assert uint16(duty.validatorIndex) == uint16(facts.validator)
  assert uint32(duty.observedTime) == uint32(facts.slot)
  let root = array[32, byte](duty.sourceRoot)
  let headRoot = array[32, byte](fixture.view.bestBlock.value.stateSnapshot.commitment.root)
  assert root == headRoot # Fresh inclusion qualification supplies the cohort, independently from older execution provenance.
  let credential = contribution.value.contributionCredential.value
  assert uint16(credential.validator) == 1 and uint32(facts.slot) == 21
  let message = array[45, byte](qualified.value.eligibleMessage.value)
  assert verify(EdPublicKey(array[32, byte](fixture.local)), EdSignature(array[64, byte](
      credential.signature)), message)
  var altered = message
  altered[44] = altered[44] xor 1
  assert not verify(EdPublicKey(array[32, byte](fixture.local)), EdSignature(array[64, byte](
      credential.signature)), altered)
  var late = guaranteeLimits()
  late.policy.accountBytes = ByteLimit(0)
  let refused = fixture.qualify(late)
  assert refused.error == WorkEligibilityError.PolicyFailure
  assert refused.policyError == ReportPolicyError.InvalidConfig

proc replacedHead(fixture: GuaranteeFixture, entry: StateEntry): ChainView =
  ## A fresh private child-state version preserves its real parent/header identity while changing one eligibility input.
  let head = fixture.view.bestBlock.value
  let parent = fixture.view.parentOf(head.blockHash)
  assert parent.error == GenesisError.None
  var state = forkStateStore(head.stateSnapshot).value
  assert state.apply([StateWrite(kind: StateWriteKind.Put, key: entry.key,
      value: entry.value)]).error == StateStoreError.None
  let changed = captured(head, state.snapshot.value, head.chainParameters)
  assert changed.error == GenesisError.None
  let selected = advanceView(genesisView(parent), changed)
  assert selected.error == ViewAdvanceError.None
  selected.value
proc guaranteeBoundaries*(fixture: GuaranteeFixture, signer, otherSigner: WorkSigner) =
  ## Existing real execution cannot bypass fresh policy/pipeline changes, source identity, explicit budgets or signer-key equality.
  let qualified = fixture.qualify(guaranteeLimits())
  assert qualified.error == WorkEligibilityError.None, "boundary eligibility: " & $qualified.error
  let report = qualified.value.eligibleReport.value
  let info = qualified.value.eligibilityInfo.value
  assert uint16(info.validator) == 1 and uint32(info.slot) == 21
  assert array[32, byte](info.head) == array[32, byte](fixture.view.bestBlock.value.blockHash)
  let absent = default(WorkSigner).signWorkContribution(qualified.value)
  assert absent.error == WorkSignerError.Uninitialized
  let wrongKey = otherSigner.signWorkContribution(qualified.value)
  assert wrongKey.error == WorkSignerError.IdentityMismatch
  let ineligible = signer.signWorkContribution(default(EligibleWorkGuarantee))
  assert ineligible.error == WorkSignerError.InvalidEligibility
  var limits = guaranteeLimits()
  limits.reportBytes = ByteLimit(0)
  let bounded = fixture.qualify(limits)
  assert bounded.error == WorkEligibilityError.LimitExceeded
  limits = guaranteeLimits()
  limits.policy.reportGas = ReportGasLimit(10000001)
  let relaxed = fixture.qualify(limits)
  assert relaxed.error == WorkEligibilityError.InvalidPolicy
  let detached = qualifyWorkGuarantee(fixture.transcript, default(WorkSubmissionHeader),
      fixture.execution,
    fixture.view, fixture.local, StateTime(21), guaranteeLimits())
  assert detached.error == WorkEligibilityError.InvalidSource
  let wrongDuty = qualifyWorkGuarantee(fixture.transcript, fixture.original, fixture.execution,
    fixture.view, topologyRecords(0, 6)[0].ed25519, StateTime(21), guaranteeLimits())
  assert wrongDuty.error == WorkEligibilityError.DutyFailure
  assert wrongDuty.dutyError.error == WorkDutyError.NotAssigned
  var changed = fixture
  let service = report.ownedReportDigest(0).value.service
  let wrongCode = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(
      ServiceMetadataBytes)).value
  changed.view = fixture.replacedHead(wrongCode)
  let policy = changed.qualify(guaranteeLimits())
  assert policy.error == WorkEligibilityError.PolicyFailure, "fresh policy: " & $policy.error
  assert policy.policyError == ReportPolicyError.WrongCodeHash
  var accumulated = newSeq[AccumulatedRow](12)
  accumulated[0] = @[report.ownedReportInfo.value.header.packageHash]
  let duplicate = accumulatedStateEntry(accumulated, guaranteeLimits().pipeline.queues).value
  changed.view = fixture.replacedHead(duplicate)
  let pipeline = changed.qualify(guaranteeLimits())
  assert pipeline.error == WorkEligibilityError.PipelineFailure, "fresh pipeline: " &
      $pipeline.error
  assert pipeline.pipelineError == ReportPackageError.DuplicatePackage
