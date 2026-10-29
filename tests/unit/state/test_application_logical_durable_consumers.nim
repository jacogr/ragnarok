# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Three genuine durable children compose supplied identity creation, preserved continuation, checkpoint, original review and managed/direct mixed proofs in both layouts.
import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../support/[collected_native_context, collected_logical_context,
    collected_supplied_context, collected_logical_services_context, current_namespace_context,
    current_namespace_transition_context,
    current_namespace_execution_context, current_repeated_logical_context,
    accumulation_execution_context,
    accumulation_current_candidate_context, application_download_chain, managed_storage_samples,
    current_logical_proof_context, current_logical_review_context]
import ../../../src/app/services
import ../../../src/app/current/logical as current_logical
import ../../../src/app/collected/supplied/[plan as collected_supplied_plan,
    state as collected_supplied_state]
import ../../../src/app/logical/[checkpoint as logical_checkpoint, proof as logical_proof,
    review as logical_review]
import ../../../src/app/proof/[query as proof_query, worker as proof_worker]
import ../../../src/app/disk/worker as disk_worker
import ../../../src/app/preparation_worker
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/app/candidate
import ../../../src/state/current/[logical as current_logical, state as current_state,
    checkpoint as current_checkpoint, review as current_review]
import ../../../src/state/account/review as account_review
import ../../../src/state/account/review/plan as account_review_plan
import ../../../src/state/inventory
import ../../../src/state/current/[globals as current_globals, profile as current_profile]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/accumulation/[round as accumulation_round, queue as accumulation_queue]
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/store
import ../../../src/state/proof/plan as proof_plan
import ../../../src/state/planned/proof as planned_proof
import ../../../src/state/proof/view as proof_view
import ../../../src/state/checkpoint
import ../../../src/chain/genesis
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, composition as state_composition,
    trie as state_trie]
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
