# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine three-core signed contexts distinguish configured ceilings, parent population and posterior eligibility.

import ./pvm_computed_storage_program
import std/assertions
import ../../src/state/computed_transition as state_computed_transition
import ../../src/state/computed_profile as state_computed_profile
import ../../src/state/computed_lookup as state_computed_lookup
import ../../src/state/computed_recent as state_computed_recent
import ../../src/state/computed_state as state_computed_state
import ../../src/state/computed_links as state_computed_links
import ../../src/state/computed_guarantee as state_computed_guarantee
import ../../src/state/computed_report as state_computed_report
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/state/report_transition as state_report_transition
import ../../src/state/store as state_store
import ../../src/state/input_refinement as state_input_refinement
import ../../src/state/availability_specifier as state_availability_specifier
import ../../src/state/export_erasure as state_export_erasure
import ../../src/state/bundle_erasure as state_bundle_erasure
import ../../src/state/erasure_layout as state_erasure_layout
import ../../src/state/erasure_words as state_erasure_words
import ../../src/state/auditable_bundle as state_auditable_bundle
import ../../src/state/extrinsic_inputs as state_extrinsic_inputs
import ../../src/state/import_inputs as state_import_inputs
import ../../src/state/import_justification as state_import_justification
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/parameters as chain_parameters
import ../../src/codec/assurances as codec_assurances
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/header as codec_header
import ../../src/codec/block_codec as codec_block_codec
import ../../src/codec/work_package as codec_work_package
import ../../src/codec/work_report as codec_work_report
import ../../src/codec/composite as codec_composite
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/state_availability as codec_state_availability
import ../../src/codec/state_authorization as codec_state_authorization
import ../../src/codec/state_disputes as codec_state_disputes
import ../../src/codec/state_privileges as codec_state_privileges
import ../../src/codec/state_statistics as codec_state_statistics
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/crypto/primitives as crypto_primitives
import ../../src/bandersnatch/bandersnatch as bandersnatch_bandersnatch
import ./pvm_computed_transition
import ./state_report_admission_context
import ./pvm_input_refinement
import ./pvm_computed_lookup
import ./pvm_computed_recent
import ./pvm_computed_report
import ./pvm_export_erasure
import ./pvm_extrinsic_inputs
import ./pvm_import_inputs

type
  ComputedRosterFixture* = object ## Mutable test handles preserve genuine original and authenticated posterior provenance.
    source*: TransitionBoundComputedReport
    original*: StateStore
    siblings*: seq[TransitionBoundComputedReport] ## Optional additional cores reuse the exact original map and successful transition.
proc rosterLinks(execution: InputRefinement, shards: ErasureShards): ComputedReportLinks =
  ## Compute actual availability with the independently selected structurally valid shard population before eligibility checking.
  let bundle = prepareAuditableBundle(execution, ByteLimit(20000)).value
  let layout = prepareErasureLayout(bundle, shards, ByteLimit(20000)).value
  let encoded = prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(1000000),
      products: FieldProductLimit(10000000))).value
  let exported = prepareExportErasure(encoded, exportErasureLimits()).value
  let available = prepareAvailabilityCommitment(exported, reportAvailabilityLimits()).value
  let report = prepareComputedReport(available, ByteLimit(100000)).value
  let transcript = prepareComputedGuarantee(report, ByteLimit(100000)).value
  prepareComputedLinks(transcript, [], ElementLimit(0)).value
proc rosterTransitionConfig*(): BlockReportConfig =
  ## Share the genuine three-core prefix policies with guarantee-bearing candidate fixtures.
  var cfg = transitionConfig()
  cfg.admission.frame.cores = CoreCount(3)
  cfg.admission.frame.validators = ValidatorCount(9)
  cfg.disputes.rosters.cores = CoreCount(3)
  cfg.disputes.rosters.validators = ElementLimit(9)
  cfg.disputes.availability.guarantee.cores = CoreCount(3)
  cfg.disputes.availability.guarantee.validators = ValidatorCount(9)
  cfg.safrole.state.validators = cfg.disputes.rosters
  cfg.availability.rosters = cfg.disputes.rosters
  cfg.availability.assignments = cfg.disputes.availability
  cfg
proc rosterFixture*(shrink = false, core = 0'u64, shards = 6'u16, rotation = 65535'u16,
    target = 0'u32, offender = false, repeatReporter = false,
    additionalCores: openArray[uint64] = [], distinctPackages = false,
        withReady = false, withRound = false, withExecution = false,
            invalidEntry = false, withComposition = false,
                withChain = false, storage = ComputedStorageMode.Disabled): ComputedRosterFixture =
  ## Re-author a three-core complete signed prefix; optional parent9 -> posterior6 is a real epoch transition.
  let base = transitionFixture(epoch = shrink, withReady = withReady, withExecution = withExecution,
      invalidEntry = invalidEntry, storage = storage)
  let cfg = rosterTransitionConfig()
  var original = base.context.original
  let assignments = availabilityStateEntry(newSeq[AvailabilityAssignment](3),
      cfg.availability.assignments).value
  let oldPoolConfig = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(16),
      maxBytes: ByteLimit(100000))
  let oldPools = decodeAuthorization(AuthorizationKind.Pools,
    original.snapshot.value.lookup(chapterKey(StateChapter(1))).value.bytes,
        oldPoolConfig).value.snapshot
  var pools = newSeq[AuthorizerRow](3)
  for coreIndex in 0..<3:
    # Preserve original authorizer membership on both existing cores and the additional configured core.
    let selected = AuthorizationCoreIndex(uint64(coreIndex mod 2))
    let count = authorizerCount(oldPools, selected).value
    pools[coreIndex] = newSeq[AuthorizerHash](count)
    for index in 0..<count:
      pools[coreIndex][index] = authorizerAt(oldPools, selected, AuthorizationIndex(uint64(index))).value
  let poolEntry = authorizationEntry(AuthorizationKind.Pools, pools, AuthorizationConfig(
    cores: CoreCount(3), maxHashes: ElementLimit(24), maxBytes: ByteLimit(100000))).value
  var writes = @[StateWrite(kind: StateWriteKind.Put, key: assignments.key,
      value: assignments.value),
    StateWrite(kind: StateWriteKind.Put, key: poolEntry.key, value: poolEntry.value)]
  if storage != ComputedStorageMode.Disabled:
    # Canonical original self-account funding enters the map before root/signing/current computation; other metadata stays exact.
    let accountKey = chapterServiceKey(StateChapter(255), ServiceIndex(42))
    var metadata = decodeServiceMetadata(original.snapshot.value.lookup(accountKey).value.bytes,
        ByteLimit(ServiceMetadataBytes)).value.metadata
    let wideFetch = storage in {ComputedStorageMode.FetchWideOffset,
        ComputedStorageMode.FetchWideIndex, ComputedStorageMode.FetchTail,
        ComputedStorageMode.FetchReadTail, ComputedStorageMode.ReadMissing,
        ComputedStorageMode.ReadCheckpointPanic, ComputedStorageMode.ReadCheckpointFault,
        ComputedStorageMode.ReadCheckpointProtection, ComputedStorageMode.ReadCheckpointWrapLoad,
      ComputedStorageMode.ReadCheckpointWrapStore, ComputedStorageMode.ReadCheckpointNegativeBranch,
        ComputedStorageMode.ReadCheckpointUntakenBranch}
    metadata.balance = AccountBalance(if wideFetch: 58'u64 elif storage ==
        ComputedStorageMode.Underfunded: 49'u64 else: 50'u64) # Eleven-byte storage needs10+2+(35+11)=58, authored before the genuine committed parent.
    let account = serviceMetadataEntry(ServiceIndex(42), metadata, ByteLimit(
        ServiceMetadataBytes)).value
    writes.add(StateWrite(kind: StateWriteKind.Put, key: account.key, value: account.value))
  if withComposition:
    # Parent statistics are genuine original serialized input, before the final root, signing and current PVM work.
    let currentCount = if withChain: 9 else: 6
    var activity = default(ActivityState)
    activity.validators[StatisticsEpoch.Current] = newSeq[ValidatorActivity](currentCount)
    activity.validators[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](6)
    activity.cores = newSeq[CoreActivity](3)
    let entry = activityStateEntry(activity, ActivityConfig(cores: CoreCount(3),
      current: ValidatorCount(uint64(currentCount)), previous: ValidatorCount(6),
          maxServices: ElementLimit(4),
      maxBytes: ByteLimit(4096))).value
    writes.add(StateWrite(kind: StateWriteKind.Put, key: entry.key, value: entry.value))
  if withExecution:
    # Complete original fixed authorization queues enter the map before its root and every current computation.
    var queues = newSeq[AuthorizerRow](3)
    for index in 0..<3:
      queues[index] = newSeq[AuthorizerHash](80) # Canonical queues allow zero identities and retain every fixed position.
    let entry = authorizationEntry(AuthorizationKind.Queues, queues, AuthorizationConfig(
      cores: CoreCount(3), maxHashes: ElementLimit(240), maxBytes: ByteLimit(7680))).value
    writes.add(StateWrite(kind: StateWriteKind.Put, key: entry.key, value: entry.value))
  if withRound:
    # Commit canonical original privileges before root/signing/execution; completed sources are never patched afterward.
    let privileges = privilegeStateEntry(PrivilegeState(manager: ServiceIndex(42),
      delegator: ServiceIndex(42), registrar: ServiceIndex(42),
      assigners: @[ServiceIndex(42), ServiceIndex(42), ServiceIndex(42)], always: @[]),
      PrivilegeConfig(cores: CoreCount(3), maxAlways: ElementLimit(2), maxBytes: ByteLimit(1000))).value
    writes.add(StateWrite(kind: StateWriteKind.Put, key: privileges.key, value: privileges.value))
  if shrink or repeatReporter or withChain:
    # Extend actual original C8 for coherent chain domains or epoch shrink; pending/staging remain six.
    let raw = original.snapshot.value.lookup(chapterKey(StateChapter(8))).value.bytes
    let active = decodeStateValidators(raw, cfg.disputes.rosters).value.value
    var records = newSeq[StateValidator](if shrink or withChain: 9 else: 6)
    for index in 0..<6: records[index] = validatorAt(active, StateValidatorIndex(uint64(index))).value
    for index in 6..<records.len:
      var seed = default(array[32, byte])
      seed[0] = byte(index+11)
      let key = importSeed(seed).value
      let originalRecord = records[index-6]
      records[index] = originalRecord
      records[index].ed25519 = StateEdKey(array[32, byte](publicKey(key).value))
    if repeatReporter:
      # Distinct current credential indices1/2 can legitimately refer to one real signing key.
      let identity = records[1].ed25519
      records[2].ed25519 = identity
    let entry = validatorEntry(ValidatorChapter.Active, records, cfg.disputes.rosters).value
    writes.add(StateWrite(kind: StateWriteKind.Put, key: entry.key, value: entry.value))
  if offender:
    # An earlier block's real excluded identity enters C5 before signing; this block has no new offender marker.
    var seed = default(array[32, byte])
    seed[0] = 16
    let excluded = importSeed(seed).value
    let entry = disputeStateEntry(DisputeState(offenders: @[OffenderKey(array[32, byte](publicKey(
        excluded).value))]), cfg.disputes.state).value
    writes.add(StateWrite(kind: StateWriteKind.Put, key: entry.key, value: entry.value))
  assert original.apply(writes).error == StateStoreError.None, "original three-core map before signing"
  let snapshot = original.snapshot.value
  let root = array[32, byte](snapshot.commitment.root)
  let headerSize = headerInfo(base.context.staged.value.admitted.admittedHeader).value.consumed
  var wire = newSeq[byte](blockInfo(base.context.candidate).value.consumed)
  assert encodeOwnedBlock(base.context.candidate, wire).error == FrameError.None
  for index in 0..<32: wire[32+index] = root[index] # Pinned header E32 parent precedes E32 prior-state root.
  if target != 0:
    # Change the authored E4 child slot before seal generation; caller selects matching existing marker shape.
    for index in 0..<4: wire[96+index] = byte((target shr (8*index)) and 255)
  var scalar = default(array[32, byte])
  scalar[0] = 1
  let key = importScalar(scalar).value
  var sealContext = newSeq[byte]("jam_fallback_seal".len+32)
  for index, octet in "jam_fallback_seal": sealContext[index] = byte(octet)
  let signature = array[96, byte](sign(key, sealContext, wire.toOpenArray(0, headerSize-97)).value)
  for index in 0..<96: wire[headerSize-96+index] = signature[
      index] # Re-sign every changed unsigned byte with the actual author key.
  close(key)
  let candidate = decodeBlock(wire, cfg.admission.frame).value.owner
  var working = original
  let staged = advanceBlockState(working, candidate, base.context.parent, cfg.admission,
    cfg.disputes, cfg.safrole, cfg.availability)
  assert staged.error == BlockTransitionError.None, "genuine three-core signed prefix: " & $staged.error
  var fixture = base.execution
  fixture.state = snapshot
  var params = fixture.parameters.encodeParameters
  params[24] = 3 # All original computation and configuration now use three configured cores.
  params[84] = byte(rotation and 255)
  params[85] = byte(rotation shr 8) # Original rotation control precedes computation and configured capture; default preserves prior fixture.
  if withRound:
    # Fixed AppendixB E8 gas fields and E2 authorization queue length are authored before original parameter capture.
    for index in 0..<8:
      params[34+index] = byte((100000'u64 shr (8*index)) and 255)
      params[58+index] = byte((1000000'u64 shr (8*index)) and 255)
    params[82] = 80
    params[83] = 0
  fixture.parameters = decodeParameters(params).value
  let info = fixture.package.workPackageInfo.value
  let item = fixture.package.workItemAt(0).value.workItemInfo.value
  var claim = info.context
  claim.anchor.bytes = array[32, byte](blake2b256(lookupWire(base.context.parent)).value)
  claim.anchorSlot = AnchorSlot(1)
  claim.stateRoot.bytes = root
  claim.accumulationRoot.bytes = default(array[32, byte])
  claim.lookupAnchor.bytes = array[32, byte](blake2b256(lookupWire(base.context.older[0])).value)
  claim.lookupSlot = LookupSlot(0)
  claim.lookupStateRoot.bytes = default(array[32, byte])
  let package = WorkPackage(host: info.host, codeHash: info.codeHash, context: claim,
    authorization: @[91'u8], configuration: @[81'u8, 82], items: @[WorkItem(service: item.service,
      codeHash: item.codeHash, refineGas: item.refineGas, accumulateGas: item.accumulateGas,
      payload: @[42'u8])])
  var packageWire = newSeq[byte](4096)
  let packageConfig = fullPackageConfig(ByteLimit(4096))
  let size = encodeWorkPackage(package, packageConfig, packageWire).value
  fixture.package = decodeWorkPackage(packageWire.toOpenArray(0, size-1), packageConfig).value.owner
  let external = verifyExtrinsicInputs(fixture.package, @[newSeq[seq[byte]](0)], extrinsicLimits()).value
  fixture.inputs = bindImportInputs(external, @[newSeq[VerifiedImport](0)], [], inputLimits()).value
  result = ComputedRosterFixture(original: original)
  for ordinal in 0..additionalCores.len:
    # Each independently executed report shares the same original snapshot, signed block and genuine staged result.
    let selectedCore = if ordinal == 0: core else: additionalCores[ordinal-1]
    if distinctPackages:
      # Distinct authored payloads produce different genuine package identities before execution and input binding.
      var selectedPackage = package
      selectedPackage.items[0].payload = @[42'u8, byte(selectedCore)]
      let selectedSize = encodeWorkPackage(selectedPackage, packageConfig, packageWire).value
      fixture.package = decodeWorkPackage(packageWire.toOpenArray(0, selectedSize-1),
          packageConfig).value.owner
      let selectedExternal = verifyExtrinsicInputs(fixture.package, @[newSeq[seq[byte]](0)],
          extrinsicLimits()).value
      fixture.inputs = bindImportInputs(selectedExternal, @[newSeq[VerifiedImport](0)], [],
          inputLimits()).value
    let selectedShards = if withChain: 9'u16 else: shards
    let links = rosterLinks(executionRun(fixture, core = selectedCore).value, ErasureShards(selectedShards))
    let admitted = validateBlockCommitments(candidate, base.context.parent, snapshot, cfg.admission)
    assert admitted.error == BlockAdmissionError.None, "genuine three-core source admission"
    let bound = bindComputedState(links, admitted).value
    var historyConfig = recentConfig()
    historyConfig.cores = CoreCount(3)
    let recent = checkComputedRecentAnchor(bound, historyConfig).value
    let lookup = checkComputedLookupAnchor(recent, base.context.older, lookupLimits()).value
    let captured = captureBlockSnapshot(lookupWire(base.context.parent), snapshot,
        fixture.parameters)
    assert captured.error == GenesisError.None, "genuine original configured three-core parent"
    let configured = bindComputedProfile(lookup, captured).value
    let source = bindComputedTransition(configured, staged, ByteLimit(4096))
    assert source.error == ComputedTransitionError.None, "exact signed source bound to genuine posterior"
    if ordinal == 0:
      result.source = source.value # Preserve the historical single-core fixture without an extra sequence allocation.
    else:
      result.siblings.add(source.value) # Only explicit multi-core callers retain additional sources.
