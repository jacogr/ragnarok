# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real download collection qualifies explicit logical sources before enqueue, preserving typed refusal and managed worker lifetimes.
import std/[assertions, envvars, syncio, monotimes, times]
import std/posix/posix
import ../../support/[current_namespace_execution_context, current_application_context,
    current_consecutive_context, accumulation_current_candidate_context, parent_profile_context,
    parent_globals_context, supplied_logical_context, current_identity_context,
    current_namespace_refresh_context, current_services_disk_samples, managed_storage_samples,
    pvm_accumulation_program, current_logical_proof_context]
import ../../../src/app/[services, options, current_block_download, current_logical_download,
    current_block_input, current_handoff, preparation_worker]
import ../../../src/rpc/server
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, block_codec, report_owned, state_layout, state_accounts,
    state_service_values]
import ../../../src/state/[parent_profile, parent_globals, parent_logical, current_logical,
    current_identities, current_request_keys, current_refresh_plan, current_logical_refresh,
    accumulation_current_update, store, block_admission, report_admission]
import ../../../src/storage/managed_manifest

type Refusal {.pure.} = enum ## Each real collected update reaches its own explicit source/policy boundary before any enqueue.
  DefaultPolicy, InvalidParent, ForeignParent, IdentityBudget, RequestBudget, ProjectionBudget,
    LogicalBudget, NewIdentity, MissingIdentity
proc storageCode(key: byte, value: seq[byte]): seq[byte] =
  ## The genuine write host overwrites key5, creates key7 or removes key5 according to the authored input.
  var payload = @[key]
  for octet in value: payload.add(octet)
  let instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, uint64(
          value.len)),
      @[10'u8, 5], @[50'u8, 0]]
  result = @[0'u8]
  for octet in guestEnvelope(instructions, payload): result.add(octet)
proc limits(): CurrentLogicalDownloadLimits =
  ## Policies are fixed independently of the received successor's claimed sizes or contents.
  CurrentLogicalDownloadLimits(identities: currentIdentityTestLimits,
      requests: namespaceRequestLimits,

reconstruction: namespaceRefreshLimits, logical: namespaceLogicalLimits())
proc wire(child: OwnedBlock): seq[byte] =
  ## Authored CE128 E4 response framing contains exactly the canonical signed block bytes.
  let size = child.blockInfo.value.consumed
  assert uint64(size) <= 0xffffffff'u64 and size <= high(int)-4
  result = newSeq[byte](size+4)
  for i in 0..<4: result[i] = byte((uint64(size) shr (8*i)) and 255)
  assert child.encodeOwnedBlock(result.toOpenArray(4, result.high)).error == FrameError.None
proc child(fixture: NamespaceExecutionFixture): OwnedBlock =
  ## Read the genuine admitted signed fixture block before any native graph lease.
  fixture.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
proc parent(owner: Services, fixture: NamespaceExecutionFixture): SelectedLogicalParent =
  ## Match complete explicit namespaces against the actual startup owner and full configured view.
  let profile = captureParentProfile(owner.chainView, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let declarations = fixture.executableNamespaceServices(owner.stateSnapshot.value)
  captureLogicalParent(globals, declarations, suppliedLogicalTestLimits).value
proc foreign(fixture: NamespaceExecutionFixture): SelectedLogicalParent =
  ## Equal-root fixture ownership cannot replace the configured Services physical parent.
  let profile = captureParentProfile(fixture.parent, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  captureLogicalParent(globals, fixture.executableNamespaceServices(
      fixture.parent.bestBlock.value.stateSnapshot), suppliedLogicalTestLimits).value
proc ready(download: var CurrentBlockDownload, owner: Services, bytes: seq[byte],
    policy: CurrentLogicalDownloadPolicy): CurrentBlockDownloadId =
  ## Retain source/policies before actual byte reception and before the managed worker may borrow any graph.
  var candidate = currentCandidateLimits()
  candidate.completion.composition.validators.services = ElementLimit(2)
  let admitted = download.begin(owner, [], CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(
      bytes.len)), ancestors: ElementLimit(4), ancestorBytes: ByteLimit(10000)),
          candidate, policy)
  assert admitted.error == CurrentBlockDownloadError.None
  assert download.requestFinished(admitted.value) == CurrentBlockDownloadError.None
  assert download.append(admitted.value, bytes, true) == CurrentBlockDownloadError.None
  assert download.stage == CurrentBlockDownloadStage.Ready
  admitted.value
proc waitDone(owner: var Services) =
  ## Scalar observations and dispatcher ticks leave all retained logical/canonical aliases untouched through Done.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    yieldCurrentDiskThread()
proc collect(download: var CurrentBlockDownload, id: CurrentBlockDownloadId,
    owner: var Services): CurrentBlockDownloadResult[PreparedCurrentChainUpdate] =
  ## A stale generation cannot collect Done or release its RPC/canonical lease.
  assert download.beginPreparation(id, owner).error == CurrentBlockDownloadError.None
  owner.waitDone()
  assert owner.preparationActive and owner.rpc.chainPaused
  assert download.collectPreparation(default(CurrentBlockDownloadId), owner).error ==
      CurrentBlockDownloadError.StaleDownload
  assert owner.preparationActive and owner.rpc.chainPaused
  result = download.collectPreparation(id, owner)
  assert not owner.preparationActive and not owner.rpc.chainPaused
proc refuse(download: var CurrentBlockDownload, owner: var Services, bytes: seq[byte],
    source, other: SelectedLogicalParent, mode: Refusal) =
  ## Every failed logical stage retires the captured policy without queueing a successful certificate or output prefix.
  var budget = limits()
  case mode
  of IdentityBudget: budget.identities.keys = ElementLimit(0)
  of RequestBudget: budget.requests.requests = ElementLimit(0)
  of ProjectionBudget: budget.reconstruction.projection.bytes = ByteLimit(0)
  of LogicalBudget: budget.logical.retainedBytes = ByteLimit(0)
  else: discard # Other controls select invalid provenance or actual identity changes, not smaller policies.
  let policy = case mode
    of DefaultPolicy: default(CurrentLogicalDownloadPolicy)
    of InvalidParent: initCurrentLogicalDownloadPolicy(default(SelectedLogicalParent), budget)
    of ForeignParent: initCurrentLogicalDownloadPolicy(other, budget)
    else: initCurrentLogicalDownloadPolicy(source, budget)
  let before = owner.stateSnapshot.value
  let id = download.ready(owner, bytes, policy)
  let completed = download.collect(id, owner)
  assert completed.error == CurrentBlockDownloadError.LogicalFailure
  let reason = completed.failure.logicalFailure
  assert download.failure.logicalFailure.error == reason.error
  case mode
  of DefaultPolicy: assert reason.error == CurrentLogicalDownloadError.InvalidPolicy
  of InvalidParent, ForeignParent, IdentityBudget, NewIdentity, MissingIdentity:
    assert reason.error == CurrentLogicalDownloadError.IdentityFailure
    let expected = case mode
      of InvalidParent: CurrentIdentityError.InvalidParent
      of ForeignParent: CurrentIdentityError.ParentMismatch
      of IdentityBudget: CurrentIdentityError.LimitExceeded
      of NewIdentity: CurrentIdentityError.NewIdentity
      else: CurrentIdentityError.MissingIdentity
    assert reason.identityFailure.error == expected
  of RequestBudget:
    assert reason.error == CurrentLogicalDownloadError.RequestKeyFailure
    assert reason.requestKeyFailure.error == CurrentRequestKeyError.LimitExceeded
  of ProjectionBudget:
    assert reason.error == CurrentLogicalDownloadError.ReconstructionFailure
    assert reason.reconstructionFailure.refusedPhase == CurrentRefreshRefusal.Projection
  of LogicalBudget:
    assert reason.error == CurrentLogicalDownloadError.LogicalPlanFailure
    assert reason.logicalPlanFailure.refusedPhase == LogicalRefreshRefusal.Retention
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
  owner.tick(0) # A failed logical successor cannot be installed by a later service turn.
  assert sameStateSnapshot(before, owner.stateSnapshot.value)
  assert download.cancel(id)
  assert download.logicalCompletion.error == CurrentLogicalDownloadError.Uninitialized
  assert owner.preparationAvailable and owner.stateProofAvailable
proc retire(download: var CurrentBlockDownload, owner: var Services, bytes: seq[byte],
    policy: CurrentLogicalDownloadPolicy) =
  ## Both immediate and Done cancellation/join retire the same pre-retained logical policy without touching it during the lease.
  let before = owner.stateSnapshot.value
  for joined in [false, true]:
    for afterDone in [false, true]:
      let id = download.ready(owner, bytes, policy)
      assert download.beginPreparation(id, owner).error == CurrentBlockDownloadError.None
      assert not download.cancel(id)
      if afterDone: owner.waitDone()
      if joined:
        assert download.retirePreparation(id, owner)
      else:
        assert download.cancelPreparation(id, owner)
        owner.waitDone()
        assert download.collectPreparation(id, owner).error == CurrentBlockDownloadError.Cancelled
        assert download.cancel(id)
      assert download.logicalCompletion.error == CurrentLogicalDownloadError.Uninitialized
      assert owner.currentAccumulationPhase == CurrentHandoffPhase.Idle
      assert sameStateSnapshot(before, owner.stateSnapshot.value)
      assert owner.preparationAvailable and owner.stateProofAvailable
proc scenario(fixture: NamespaceExecutionFixture, layout: int, mutation = false,
    create = false) {.raises.} =
  ## Each physical backend qualifies actual adapter publication and strict reopen of only the successfully adopted prefix.
  var path = "pvm-logical-download-chain"
  var database = "pvm-logical-download-state-" & $layout
  writeFile(path, fixture.parent.bestBlock.value.currentApplicationText)
  defer:
    discard posix.unlink(path.toCString())
    if layout == 2: removeManagedSample(database, [ManagedEpoch(1)])
    elif layout == 1: discard posix.unlink(database.toCString()) # Clean only the explicit namespace after joined owner shutdown.
  var options = default(Options)
  if layout == 0:
    assert parseOptions(@["server", "--with-state", "--chain", path], options)
  else: options = currentDiskOptions(path, database, layout == 2, 0)
  var download = default(CurrentBlockDownload)
  var owner = default(Services)
  var active = default(CurrentBlockDownloadId)
  defer:
    discard download.retirePreparation(active, owner)
    owner.close() # Joined shutdown precedes the receiver's custom destruction on every raised path.
  assert owner.start(options, "logical download adapter")
  let initial = owner.stateSnapshot.value
  let source = owner.parent(fixture)
  let other = fixture.foreign
  let bytes = fixture.child.wire
  if mutation:
    download.refuse(owner, bytes, source, other, if create: Refusal.NewIdentity else: Refusal.MissingIdentity)
  else:
    for mode in Refusal.DefaultPolicy..Refusal.LogicalBudget:
      download.refuse(owner, bytes, source, other, mode)
    var frozen = limits()
    let firstPolicy = initCurrentLogicalDownloadPolicy(source, frozen)
    frozen.identities.keys = ElementLimit(0) # Detached caller budget edits cannot change the already retained policy.
    download.retire(owner, bytes, firstPolicy)
    var logical = default(CurrentLogicalState)
    let storage = serviceStorageKey(ServiceIndex(99), @[5'u8], ByteLimit(1)).value
    for index in 0..<3:
      # Each new child is signed against the actual adopted predecessor; only the first uses the configured logical seed.
      let next = if index == 0: bytes else: currentEmptyChild(owner.chainView.bestBlock.value).wire
      let policy = if index == 0: firstPolicy else: initCurrentLogicalDownloadPolicy(logical,
          limits())
      let before = owner.stateSnapshot.value
      active = download.ready(owner, next, policy)
      let completed = download.collect(active, owner)
      assert completed.error == CurrentBlockDownloadError.None
      assert download.stage == CurrentBlockDownloadStage.Idle
      logical = download.logicalCompletion.value
      assert sameStateSnapshot(logical.logicalProducer.currentUpdateState,
          completed.value.currentUpdateState)
      assert sameStateSnapshot(before, owner.stateSnapshot.value)
      assert owner.currentAccumulationPhase == CurrentHandoffPhase.Pending
      assert logical.logicalProducer.currentUpdateState.lookup(storage).value.bytes == @[17'u8, 18, 19]
      owner.tick(0)
      if layout != 0:
        owner.waitCurrentDiskDone()
        owner.tick(0) # Matching native disk collection ends the second graph lease before inspecting any retained result.
      assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
      assert owner.takeCurrentAccumulation().error == CurrentHandoffError.None
      assert sameStateSnapshot(owner.stateSnapshot.value,
          logical.logicalProducer.currentUpdateState)
      if index == 0:
        let next = currentEmptyChild(owner.chainView.bestBlock.value).wire
        download.refuse(owner, next, source, source,
            Refusal.ForeignParent) # The originally valid configured seed is stale after actual adoption; it cannot authorize the next child.
    assert initial.lookup(storage).value.bytes.len == 0
  let finalState = owner.stateSnapshot.value
  let retained = owner.chainView.retainedCount
  assert retained == (if mutation: 1 else: 4)
  owner.close()
  if layout != 0:
    assert owner.start(options, "strict logical download reopen")
    assert owner.chainView.retainedCount == retained
    equalCurrentDiskMap(owner.stateSnapshot.value, finalState)
    owner.close()
proc main() {.raises.} =
  ## Actual host writes and original complete namespaces make producer identity changes observable without fabricated State certificates.
  let blank = default(CurrentLogicalDownloadResult)
  assert blank.error == CurrentLogicalDownloadError.Uninitialized
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let updated = namespaceExecutionFixture(base, namespaceHaltCode(), storageCode(5, @[17'u8, 18, 19]))
  let added = namespaceExecutionFixture(base, namespaceHaltCode(), storageCode(7, @[21'u8, 22]))
  let deleted = namespaceExecutionFixture(base, namespaceHaltCode(), storageCode(5, @[]))
  for layout in 0..2:
    scenario(updated, layout)
    scenario(added, layout, true, true)
    scenario(deleted, layout, true, false)
  echo "PVM current logical download passed"
try:
  main()
except:
  quit(2) # Execution, exact refusal, publication and strict-reopen failures cannot satisfy this native contract.
