# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual managed preparation and proof leases reject both logical source alternatives before canonical access.
import std/[assertions, cmdline, syncio, strutils, monotimes, times]
import std/posix/posix
import ../../src/app/logical_checkpoint_import
import ../../src/app/logical_export
import ../../src/app/logical_service_proof
import ../../src/app/current_logical
import ../../src/state/supplied_services
import ../../src/app/frozen_supplied
import ../../src/app/[logical_seed, collected_supplied_plan, collected_supplied_state,
    logical_checkpoint, logical_review]
import ../../src/state/account_review_plan
import ../../src/app/[services, current_logical, preparation_worker, current_block_input,
    proof_worker, current_handoff, disk_worker]
import ../../src/state/[parent_logical, current_logical, proof_plan, accumulation_current_update,
    accumulation_round, accumulation_queue, report_admission, block_transition, block_admission]
import ../../src/codec/[bounded, report_owned, state_layout, composite]
import ../../src/chain/[provider, genesis]
import ../support/[current_repeated_logical_context, collected_logical_context,
    collected_logical_services_context, accumulation_current_candidate_context, current_logical_proof_context]
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
  if mode.endsWith("-logical-checkpoint-import"):
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
