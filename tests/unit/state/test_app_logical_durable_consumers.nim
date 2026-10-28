# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Three genuine durable children compose supplied identity creation, preserved continuation, checkpoint, original review and managed/direct mixed proofs in both layouts.
import std/assertions
import std/syncio
import std/monotimes
import std/times
import std/posix/posix
import ../../support/app_collected_native_context
import ../../support/app_collected_logical_context
import ../../support/app_collected_supplied_context
import ../../support/app_collected_logical_services_context
import ../../support/state_current_namespace_context
import ../../support/state_current_namespace_transition_context
import ../../support/state_current_namespace_execution_context
import ../../support/state_current_repeated_logical_context
import ../../support/state_accumulation_execution_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/app_download_chain
import ../../support/app_managed_storage_samples
import ../../support/state_current_logical_proof_context
import ../../support/state_current_logical_review_context
import ../../../src/app/services as app_services
import ../../../src/app/current_logical as app_current_logical
import ../../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../../src/app/logical_checkpoint as app_logical_checkpoint
import ../../../src/app/logical_proof as app_logical_proof
import ../../../src/app/logical_review as app_logical_review
import ../../../src/app/proof_query as app_proof_query
import ../../../src/app/proof_worker as app_proof_worker
import ../../../src/app/disk_worker as app_disk_worker
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/app/candidate as app_candidate
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_checkpoint as state_current_checkpoint
import ../../../src/state/current_review as state_current_review
import ../../../src/state/account_review as state_account_review
import ../../../src/state/account_review_plan as state_account_review_plan
import ../../../src/state/inventory as state_inventory
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/chain/genesis as chain_genesis
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_trie as codec_state_trie
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Scalar native scheduling never retains, drops or reads a leased canonical owner.
proc waitDisk(owner: var Services) =
  ## Publication Done retains exclusion until the following host tick performs actual receipt collection.
  let start = getMonoTime()
  while owner.diskPublicationPhase != DiskWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    discard pauseMicros(1000)
proc waitProof(owner: var Services) =
  ## Proof Done retains the graph until matching managed collection.
  let start = getMonoTime()
  while owner.stateProofPhase != ProofWorkerPhase.Done:
    assert (getMonoTime()-start).inSeconds < 20
    discard pauseMicros(1000)
proc run(managed: bool) {.raises.} =
  ## All original namespaces/code enter signed roots; actual Services preparation and disk receipts supply every successor/adoption authority.
  let value = @[91'u8, 92, 93]
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = namespaceStorageCode(value)
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let origin = namespaceTransitionFixture(nativeBase(), options)
  let fixture = CurrentRepeatedLogicalFixture(first: origin)
  var declarations = origin.services
  declarations[1].storage.add(StateStorageItem(key: @[7'u8], value: value))
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-logical-durable-consumers-chain.json"
  var database = "application-logical-durable-consumers-" & $getMonoTime().ticks
  discard startLogicalServices(owner, fixture, path, database, managed)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
    if managed: removeManagedSample(database, [ManagedEpoch(1)])
    else: discard posix.unlink(database.toCString())
  let blockOwner = origin.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  var wire = currentWire(blockOwner)
  var logical = default(CurrentLogicalState)
  let selection = logicalProofPlan()
  let proofPolicy = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  var reviewPolicy = logicalReviewTestLimits()
  reviewPolicy.audit.planning = ElementLimit(64)
  reviewPolicy.audit.footprints.checks = ElementLimit(64)
  var lastProof: seq[byte] = @[]
  var lastCheckpoint: seq[byte] = @[]
  var lastRoot = default(StateRoot)
  for slot in 2'u32..4'u32:
    let original = owner.stateSnapshot.value
    var policies = currentCandidateLimits()
    if slot > 2: policies.completion.composition.validators.services = ElementLimit(2)
    let ancestors = if slot == 2: origin.source.older else: @[]
    let ticket = beginManagedCurrent(owner, input, wire, ancestors, policies)
    owner.waitManagedPreparation()
    let receipt = owner.collectPreparation(ticket)
    let update = receipt.currentValue.value
    if slot == 2:
      let supplied = successorDeclarations(update, declarations)
      let plan = owner.planCollectedSupplied(receipt, collectedSuppliedTestLimits()).value
      logical = owner.executeCollectedSupplied(plan, supplied).value
    else:
      logical = owner.refreshCollectedLogical(receipt, logical, collectedLogicalTestLimits()).value
    assert sameStateSnapshot(owner.stateSnapshot.value, original), "host qualification never publishes"
    let capsule = owner.captureLogicalCheckpoint(logical, ByteLimit(1048576)).value
    let reviewed = owner.reviewLogicalState(logical, reviewPolicy).value
    let query = captureLogicalProofQuery(logical, selection, proofPolicy).value
    let root = logical.currentLogicalContext.value.state.commitment.root
    let selected = update.currentUpdateChild.blockHash
    assert capsule.currentCheckpointFinalized.error == CurrentCheckpointError.NoFinality
    assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
    owner.tick(0)
    assert owner.diskPublicationActive
    owner.waitDisk()
    assert owner.diskPublicationActive and owner.currentAccumulationPhase ==
        CurrentHandoffPhase.Publishing
    owner.tick(0) # Actual durable collection ends the lease and installs before any retained consumer alias is touched.
    assert not owner.diskPublicationActive
    assert owner.takeCurrentAccumulation.error == CurrentHandoffError.None
    assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
    let admittedProof = owner.beginStateProof(selected, selection, proofPolicy.query).value
    owner.waitProof()
    assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
        ProofWorkerCompletionKind.Uninitialized
    assert owner.stateProofActive
    let completedProof = owner.collectStateProof(admittedProof)
    assert completedProof.kind == ProofWorkerCompletionKind.Completed
    let managedBytes = completedProof.value.value.bytes(proofPolicy.query.wireBytes).value
    let directBytes = executeProofQuery(query).value.bytes(proofPolicy.query.wireBytes).value
    assert managedBytes == directBytes, "logical original target and managed selected target produce identical canonical RPV1"
    let view = decodePlannedProofs(managedBytes, selection, root, proofPolicy.query.view,
      proofPolicy.query.proof, proofPolicy.query.aggregate, proofPolicy.query.wireBytes).value
    checkLogicalProof(logical, view, slot)
    assert sameStateInventory(reviewed.logicalCurrentReview.value.currentAccountReview.value.reviewInventory.value,
      logical.currentLogicalSource.value.currentStateInventory.value)
    lastProof = managedBytes
    lastCheckpoint = capsule.copyCurrentCheckpoint(ByteLimit(1048576)).value
    lastRoot = root
    if slot < 4: wire = currentWire(signedChild(update.currentUpdateChild))
  owner.close() # Join precedes every final source/consumer retirement and detached decode.
  let detached = decodePlannedProofs(lastProof, selection, lastRoot, proofPolicy.query.view,
    proofPolicy.query.proof, proofPolicy.query.aggregate, proofPolicy.query.wireBytes).value
  checkLogicalProof(logical, detached, 4)
  let restored = decodeFullCheckpoint(lastCheckpoint, lastRoot, genesisStoreLimits(), ByteLimit(1048576)).value
  assert array[32, byte](restored.snapshot.value.commitment.root) == array[32, byte](lastRoot)
proc main() {.raises.} =
  ## Both existing durable layouts use the same actual complete-source and native lease contracts.
  run(false)
  run(true)
  echo "application-logical-durable-consumers: ok"
try:
  main()
except:
  quit(2) # No source scope, cancellation status, root equality or detached map can manufacture real adoption authority.
