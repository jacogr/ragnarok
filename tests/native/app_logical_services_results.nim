# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual managed preparation and proof leases reject both logical source alternatives before canonical access.
import std/assertions
import std/cmdline
import std/syncio
import std/strutils
import std/monotimes
import std/times
import std/posix/posix
import ../../src/state/logical_continuation as state_logical_continuation
import ../../src/state/storage_logical_continuation as state_storage_logical_continuation
import ../../src/app/logical_source_export as app_logical_source_export
import ../../src/app/logical_code_proof as app_logical_code_proof
import ../../src/app/paged_logical_proof as app_paged_logical_proof
import ../../src/app/full_logical_proof as app_full_logical_proof
import ../../src/state/code_availability as state_code_availability
import ../../src/app/logical_code as app_logical_code
import ../../src/state/store as state_store
import ../../src/app/logical_checkpoint_import as app_logical_checkpoint_import
import ../../src/app/logical_export as app_logical_export
import ../../src/app/logical_service_proof as app_logical_service_proof
import ../../src/app/current_logical as app_current_logical
import ../../src/state/supplied_services as state_supplied_services
import ../../src/app/frozen_supplied as app_frozen_supplied
import ../../src/app/logical_seed as app_logical_seed
import ../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../src/app/logical_checkpoint as app_logical_checkpoint
import ../../src/app/logical_review as app_logical_review
import ../../src/state/account_review_plan as state_account_review_plan
import ../../src/app/services as app_services
import ../../src/app/current_logical as app_current_logical
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/proof_worker as app_proof_worker
import ../../src/app/current_handoff as app_current_handoff
import ../../src/app/disk_worker as app_disk_worker
import ../../src/state/parent_logical as state_parent_logical
import ../../src/state/current_logical as state_current_logical
import ../../src/state/proof_plan as state_proof_plan
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/composite as codec_composite
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
import ../support/state_current_repeated_logical_context
import ../support/app_collected_logical_context
import ../support/app_collected_logical_services_context
import ../support/state_accumulation_current_candidate_context
import ../support/state_current_logical_proof_context
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Scalar-only native deadline polling cannot touch a leased canonical graph.
proc main() {.raises.} =
  ## Every probe starts real managed native work; setup or ordinary exceptions never count as contract failure.
  let mode = paramStr(1)
  let raw = readFile("tests/fixtures/state-report.bin")
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var database = ""
  if mode.startsWith("publication"):
    database = "build/application-logical-guard-state-" & mode
    discard posix.unlink(database.toCString()) # Retire only this strict probe's exact previous test-owned journal before startup.
  let source = startLogicalServices(owner, fixture, "build/application-logical-guard-chain.json", database)
  defer: owner.close() # Positive joined cleanup retires either native borrower before source/input aliases.
  if mode == "control":
    let receipt = default(PreparationCompletion)
    assert owner.refreshCollectedLogical(receipt, source, collectedLogicalTestLimits()).error ==
        CollectedLogicalError.NoCompletion
    return
  if mode.startsWith("publication"):
    let bound = fixture.first.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted
    let wire = currentWire(bound.admittedBlock)
    let ticket = beginManagedCurrent(owner, input, wire, fixture.first.source.older,
        currentCandidateLimits())
    owner.waitManagedPreparation()
    let receipt = owner.collectPreparation(ticket)
    assert owner.enqueueCurrentAccumulation(receipt.currentValue.value) ==
        CurrentHandoffAdmission.None
    owner.tick(0)
    assert owner.diskPublicationActive
    let start = getMonoTime()
    while owner.diskPublicationPhase != DiskWorkerPhase.Done:
      assert (getMonoTime()-start).inSeconds < 20
      discard pauseMicros(1000)
    assert owner.diskPublicationActive # Durable Done still borrows all canonical aliases until actual collection.
  elif mode.startsWith("preparation"):
    let ticket = beginManagedCurrent(owner, input, [255'u8], [], currentCandidateLimits())
    owner.waitManagedPreparation()
    assert owner.cancelPreparation(ticket)
    assert owner.preparationActive # Done plus cancellation retains the actual graph lease.
  else:
    let selected = owner.chainView.bestBlock.value.blockHash
    let plan = captureStateProofPlan([chapterKey(StateChapter(11))], ElementLimit(1)).value
    let ticket = owner.beginStateProof(selected, plan, logicalProofLimits()).value
    let start = getMonoTime()
    while owner.stateProofPhase != ProofWorkerPhase.Done:
      assert (getMonoTime()-start).inSeconds < 20
      discard pauseMicros(1000)
    assert owner.cancelStateProof(ticket)
    assert owner.stateProofActive # Proof Done plus cancellation keeps the same canonical exclusion.
  let receipt = default(PreparationCompletion)
  let logical = default(CurrentLogicalState)
  if mode.endsWith("-namespace-parent"):
    discard owner.continueCurrentNamespaces(default(SelectedLogicalParent), default(
        PreparedCurrentChainUpdate), default(LogicalContinuationLimits))
  elif mode.endsWith("-namespace-current"):
    discard owner.continueCurrentNamespaces(logical, default(PreparedCurrentChainUpdate), default(LogicalContinuationLimits))
  elif mode.endsWith("-storage-parent"):
    discard owner.continueCurrentStorage(default(SelectedLogicalParent), default(
        PreparedCurrentChainUpdate), default(StorageContinuationLimits))
  elif mode.endsWith("-storage-current"):
    discard owner.continueCurrentStorage(logical, default(PreparedCurrentChainUpdate), default(StorageContinuationLimits))
  elif mode.endsWith("-source-export-plan"):
    discard owner.planLogicalSourceExport(logical, default(LogicalSourceExportLimits))
  elif mode.endsWith("-source-export"):
    discard owner.executeLogicalSourceExport(default(LogicalSourceExportPlan))
  elif mode.endsWith("-code-proof"):
    discard owner.planLogicalCodeProof(logical, ServiceIndex(0), default(LogicalCodeProofLimits))
  elif mode.endsWith("-page-plan"):
    discard owner.planLogicalProofPages(logical, default(FullLogicalProofLimits), default(LogicalProofPageLimits))
  elif mode.endsWith("-full-logical-proof-plan"):
    discard owner.planFullLogicalProof(logical, default(FullLogicalProofLimits))
  elif mode.endsWith("-logical-code"):
    discard owner.auditLogicalCodeAvailability(logical, default(CodeAvailabilityLimits))
  elif mode.endsWith("-logical-checkpoint-import"):
    discard owner.importLogicalCheckpoint(logical, [], default(StateStoreLimits), ByteLimit(0))
  elif mode.endsWith("-logical-export-plan"):
    discard owner.planLogicalExport(logical, default(SuppliedServicesLimits))
  elif mode.endsWith("-logical-export-execution"):
    discard owner.executeLogicalExport(default(LogicalExportPlan))
  elif mode.endsWith("-logical-service-selection"):
    discard owner.planLogicalServiceProof(logical, ServiceIndex(99), default(LogicalServiceProofLimits))
  elif mode.endsWith("-collected-plan-selected"):
    discard owner.planCollectedLogical(receipt, default(SelectedLogicalParent), default(CollectedLogicalLimits))
  elif mode.endsWith("-collected-plan-current"):
    discard owner.planCollectedLogical(receipt, logical, default(CollectedLogicalLimits))
  elif mode.endsWith("-collected-plan-execution"):
    discard owner.executeCollectedLogical(default(CollectedLogicalPlan))
  elif mode.endsWith("-frozen-supplied-capture"):
    let plan = default(CollectedSuppliedPlan)
    discard owner.freezeCollectedSupplied(plan, [], default(SuppliedServicesLimits))
  elif mode.endsWith("-frozen-supplied-execution"):
    discard owner.executeFrozenSupplied(default(FrozenSuppliedInput))
  elif mode.endsWith("-seed"):
    discard owner.captureLogicalSeed([], default(LogicalSeedLimits))
  elif mode.endsWith("-supplied-plan"):
    discard owner.planCollectedSupplied(receipt, default(CollectedSuppliedLimits))
  elif mode.endsWith("-supplied-execution"):
    let plan = default(CollectedSuppliedPlan)
    discard owner.executeCollectedSupplied(plan, [])
  elif mode.endsWith("-logical-checkpoint"):
    discard owner.captureLogicalCheckpoint(logical, ByteLimit(1048576))
  elif mode.endsWith("-logical-review-plan"):
    discard owner.planLogicalReview(logical, default(AccountReviewPlanLimits))
  elif mode.endsWith("-logical-review-execution"):
    let plan = default(LogicalReviewPlan)
    discard owner.executeLogicalReview(plan)
  elif mode.endsWith("-logical-review"):
    discard owner.reviewLogicalState(logical, default(AccountReviewPlanLimits))
  elif mode.endsWith("selected"):

    let empty = default(SelectedLogicalParent)
    discard owner.refreshCollectedLogical(receipt, empty, collectedLogicalTestLimits())
  else:
    let empty = default(CurrentLogicalState)
    discard owner.refreshCollectedLogical(receipt, empty, collectedLogicalTestLimits())
try:
  main()
except:
  quit(2) # Only exact AssertionDefect exits satisfy the strict negative verdicts.
