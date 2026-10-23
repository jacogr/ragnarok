# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-owned real Services preparation/collection and independently bounded State logical refresh for actual host consumers.
import std/[assertions, monotimes, times]
import std/posix/posix
import ./[accumulation_current_chain_context, parent_profile_context, parent_globals_context, supplied_logical_context]
import ../../src/chain/[provider, genesis, parameters]
import ../../src/codec/state_composition
import ../../src/state/[parent_profile, parent_globals, parent_logical]
import ./[current_identity_context, current_namespace_refresh_context,
    current_logical_proof_context, current_services_disk_samples]
import ../../src/app/[services, preparation_worker, current_block_input, candidate, proof_query, proof_worker]
import ../../src/rpc/server
import ../../src/codec/[bounded, block_codec, state_layout, state_accounts, state_service_values]
import ../../src/state/[accumulation_current_update, current_identities, current_request_keys,
    current_refresh_plan, current_logical_refresh, current_logical, planned_proof, proof_view, store]
type LogicalPreparation = object ## Only scalar receiver/ticket identities cross native wait/cancel/collection boundaries.
  ticket: PreparationTicket
  input: CurrentBlockInputId
proc beginLogicalChild(owner: var Services, input: var CurrentBlockInput, child: OwnedBlock,
    policies: CurrentCandidateLimits): LogicalPreparation {.raises.} =
  ## Bind the actual canonical parent and capture raw wire before granting the worker an exclusive graph lease.
  var wire = newSeq[byte](child.blockInfo.value.consumed)
  assert child.encodeOwnedBlock(wire).error == FrameError.None
  let received = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [],
      CurrentBlockInputLimits(blockBytes: ByteLimit(uint64(wire.len)),
          ancestorBytes: ByteLimit(10000), ancestors: ElementLimit(4)), policies)
  assert received.error == CurrentBlockInputError.None
  assert input.append(received.value, wire, true) == CurrentBlockInputError.None
  let ticket = owner.beginPreparation(input, received.value)
  assert ticket.error == PreparationError.None
  LogicalPreparation(ticket: ticket.value, input: received.value)
proc waitLogicalPreparation(owner: var Services) =
  ## Native completion is observed through synchronized scalars; Done does not release the canonical graph or RPC exclusion.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    owner.tick(0)
    var delay = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(delay, remaining) # No retained graph owner is accessed, copied or retired during native borrowing.
  assert owner.preparationActive and owner.rpc.chainPaused
proc collectLogicalChild*(owner: var Services, input: var CurrentBlockInput, child: OwnedBlock,
    policies: CurrentCandidateLimits): PreparedCurrentChainUpdate {.raises.} =
  ## Only matching collection exposes a genuine update; all raw/canonical owners remain untouched while the worker can borrow them.
  let job = owner.beginLogicalChild(input, child, policies)
  owner.waitLogicalPreparation()
  assert owner.collectPreparation(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized
  assert owner.preparationActive and owner.preparationPhase == PreparationPhase.Done
  let completed = owner.collectPreparation(job.ticket)
  assert completed.kind == PreparationCompletionKind.CurrentCompleted
  assert completed.currentValue.error == CurrentBlockInputError.None
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.preparationAvailable and owner.stateProofAvailable
  completed.currentValue.value
proc cancelLogicalChild*(owner: var Services, input: var CurrentBlockInput, child: OwnedBlock,
    policies: CurrentCandidateLimits, afterDone: bool) {.raises.} =
  ## Immediate and completed genuine jobs return only Cancelled; stale collection cannot release capacity or any graph alias.
  let job = owner.beginLogicalChild(input, child, policies)
  if afterDone: owner.waitLogicalPreparation() # This branch guarantees an actual successful native result is discarded by cancellation.
  assert owner.cancelPreparation(job.ticket)
  owner.waitLogicalPreparation()
  assert owner.collectPreparation(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized
  assert owner.preparationActive and owner.rpc.chainPaused
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  assert owner.collectPreparation(job.ticket).kind == PreparationCompletionKind.Cancelled
  assert not owner.preparationActive and not owner.rpc.chainPaused
  discard input.cancel(job.input) # A skipped job can leave Ready raw input; only the now-open host gate can retire it.
  assert input.stage == CurrentBlockInputStage.Idle
  assert owner.preparationAvailable and owner.stateProofAvailable
proc joinLogicalChild*(owner: var Services, input: var CurrentBlockInput, child: OwnedBlock,
    policies: CurrentCandidateLimits, afterDone: bool) {.raises.} =
  ## Joined shutdown is the sole lease release for this uncollected genuine preparation; every outer logical/canonical alias stays untouched until close returns.
  let job = owner.beginLogicalChild(input, child, policies)
  if afterDone: owner.waitLogicalPreparation() # Done remains leased and cannot authorize retirement without collection or join.
  owner.close()
  assert not owner.preparationActive and not owner.rpc.chainPaused
  assert owner.collectPreparation(job.ticket).kind == PreparationCompletionKind.Uninitialized
  discard input.cancel(job.input) # Raw receiver retirement occurs strictly after joined worker shutdown.
  assert input.stage == CurrentBlockInputStage.Idle
proc refreshCollectedIdentities*(source: PreservedCurrentIdentities): CurrentLogicalState =
  ## Every actual opaque predecessor is checked under explicit independent namespace policies before extraction; no enqueue or installation occurs here.
  let keys = captureCurrentRequestKeys(source, namespaceRequestLimits)
  assert keys.error == CurrentRequestKeyError.None
  let reconstruction = planCurrentRefresh(keys.value, namespaceRefreshLimits)
  assert reconstruction.error == CurrentRefreshPlanError.None
  let plan = planCurrentLogicalRefresh(reconstruction.value, namespaceLogicalLimits())
  assert plan.error == LogicalRefreshPlanError.None
  let logical = executeCurrentLogicalRefresh(plan.value)
  assert logical.error == LogicalRefreshError.None
  logical.value
proc proveLogicalCurrent*(owner: var Services, logical: CurrentLogicalState) {.raises.} =
  ## Independently select the installed logical producer's root and exact proof plan before native borrowing; no retained logical/canonical owner is touched until matching collection.
  let update = logical.logicalProducer
  let selected = update.currentUpdateChildContext.hash
  let root = update.currentUpdateState.commitment.root
  let plan = logicalProofPlan()
  let limits = logicalProofLimits()
  let ticket = owner.beginStateProof(selected, plan, limits)
  assert ticket.error == StateProofAdmissionError.None
  let started = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-started).inSeconds < 20
    yieldCurrentDiskThread()
  assert owner.stateProofActive and owner.rpc.chainPaused
  assert not owner.preparationAvailable and not owner.stateProofAvailable
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized
  assert owner.stateProofActive and owner.stateProofPhase == ProofWorkerPhase.Done
  let completed = owner.collectStateProof(ticket.value)
  assert completed.kind == ProofWorkerCompletionKind.Completed
  assert completed.value.error == ProofQueryError.None
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  assert array[32, byte](completed.value.value.blockHash) == array[32, byte](selected)
  assert array[32, byte](completed.value.value.stateRoot) == array[32, byte](root)
  let wire = completed.value.value.bytes(limits.wireBytes)
  assert wire.error == ProofQueryError.None
  let authenticated = decodePlannedProofs(wire.value, plan, root, limits.view, limits.proof,
      limits.aggregate, limits.wireBytes)
  assert authenticated.error == ProofViewError.None
  let view = authenticated.value
  assert view.len == 18
  for i in 1..16:
    # Every actual chapter value is authenticated under the independently selected logical root; response bytes supply no trust policy.
    let key = chapterKey(StateChapter(uint8(i)))
    assert view.lookup(key).value.bytes == update.currentUpdateState.lookup(key).value.bytes
  let key = serviceStorageKey(ServiceIndex(99), @[5'u8], ByteLimit(1)).value
  assert view.lookup(key).value.present and view.lookup(key).value.bytes == @[17'u8, 18, 19]
  assert not view.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(123456))).value.present
  assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
  assert owner.preparationAvailable and owner.stateProofAvailable
proc retireLogicalProof*(owner: var Services, logical: CurrentLogicalState,
    afterDone: bool, joined = false) {.raises.} =
  ## Real Services proof work borrows the canonical graph shared with this retained logical source; cancellation and joined stop grant no successful response prefix.
  let update = logical.logicalProducer
  let selected = update.currentUpdateChildContext.hash
  let plan = logicalProofPlan()
  let limits = logicalProofLimits()
  let ticket = owner.beginStateProof(selected, plan, limits)
  assert ticket.error == StateProofAdmissionError.None
  if joined and not afterDone:
    owner.stopStateProofs() # Immediate joined retirement cannot inspect any logical/query/canonical owner before it returns.
    assert owner.collectStateProof(ticket.value).kind == ProofWorkerCompletionKind.Uninitialized
  else:
    if not afterDone:
      assert owner.cancelStateProof(ticket.value) # Immediate cancellation can skip execution but cannot release the graph lease.
    let started = getMonoTime()
    while owner.stateProofPhase != ProofWorkerPhase.Done:
      assert (getMonoTime()-started).inSeconds < 20
      yieldCurrentDiskThread()
    if afterDone:
      assert owner.cancelStateProof(ticket.value) # This branch discards a genuinely completed proof after observing Done.
    assert owner.stateProofActive and owner.rpc.chainPaused
    assert not owner.preparationAvailable and not owner.stateProofAvailable
    assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
        ProofWorkerCompletionKind.Uninitialized
    assert owner.stateProofActive and owner.stateProofPhase == ProofWorkerPhase.Done
    if joined:
      owner.stopStateProofs() # Even a completed cancelled proof stays borrowed until this exact joined stop returns.
      assert owner.collectStateProof(ticket.value).kind == ProofWorkerCompletionKind.Uninitialized
    else:
      assert owner.collectStateProof(ticket.value).kind == ProofWorkerCompletionKind.Cancelled
  assert not owner.stateProofActive and not owner.rpc.chainPaused
  assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
  assert owner.preparationAvailable and owner.stateProofAvailable
proc checkRepricedLogicalSeed*(owner: Services, update: PreparedCurrentChainUpdate,
    declarations: openArray[StateService]) =
  ## A structurally recaptured source with the same physical map and cardinalities but another economic parameter tuple cannot authorize the actual collected successor.
  let view = owner.chainView
  assert view.finalizedBlock.error != GenesisError.None
  let original = view.bestBlock.value.chainParameters
  var wire = original.encodeParameters
  assert wire.len > 8 and wire[8] == 0
  wire[8] = 1 # Only the explicit fixture's original zero byte-price changes; this is not a production parameter override.
  let alternative = decodeParameters(wire).value
  assert alternative.get(coreCount) == original.get(coreCount)
  assert alternative.get(epochPeriod) == original.get(epochPeriod)
  assert alternative.encodeParameters != original.encodeParameters
  var history: seq[BlockSnapshotResult] = @[]
  for i in 0..<view.retainedCount:
    # Structural snapshot capture preserves each actual state/header owner while explicitly selecting the different full configured tuple.
    let snapshot = view.retainedBlockAt(RetainedBlockIndex(i)).value
    let captured = captureBlockSnapshot(currentChainBytes(snapshot.header), snapshot.stateSnapshot, alternative)
    assert captured.error == GenesisError.None
    assert uint64(captured.value.activeValidators) == uint64(snapshot.activeValidators)
    history.add(captured)
  let repriced = restoreLocalChainView(history).value
  let profile = captureParentProfile(repriced, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let parent = captureLogicalParent(globals, declarations, suppliedLogicalTestLimits)
  assert parent.error == ParentLogicalError.None
  assert sameStateSnapshot(profile.parentContext.value.state, update.currentUpdatePriorState)
  assert preserveCurrentIdentities(parent.value, update, currentIdentityTestLimits).error ==
      CurrentIdentityError.ViewMismatch
proc checkShortLogicalSeed*(owner: Services, update: PreparedCurrentChainUpdate,
    declarations: openArray[StateService]) =
  ## A successful complete source on the exact same physical best head cannot substitute for the original whole selected history.
  let view = owner.chainView
  assert view.retainedCount > 1 and view.finalizedBlock.error != GenesisError.None
  let shortened = restoreLocalChainView([view.bestBlock]).value
  assert shortened.retainedCount == 1
  let profile = captureParentProfile(shortened, parentProfileTestLimits).value
  let globals = qualifyParentGlobals(profile, parentGlobalsTestLimits).value
  let parent = captureLogicalParent(globals, declarations, suppliedLogicalTestLimits)
  assert parent.error == ParentLogicalError.None
  assert sameStateSnapshot(profile.parentContext.value.state, update.currentUpdatePriorState)
  assert preserveCurrentIdentities(parent.value, update, currentIdentityTestLimits).error ==
      CurrentIdentityError.ViewMismatch
