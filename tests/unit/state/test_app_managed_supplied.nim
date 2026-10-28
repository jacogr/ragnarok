# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed supplied qualification consumes the actual collected successor and remains separate from adoption and listener lifetime.
import std/assertions
import std/syncio
import std/posix/posix
import ../../support/app_collected_native_context
import ../../support/app_collected_supplied_context
import ../../support/app_collected_logical_services_context
import ../../support/app_collected_logical_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/state_supplied_services_context
import ../../../src/app/services as app_services
import ../../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/store as state_store
proc main() {.raises.} =
  ## Services owns a separately reparsed physical map; only its genuine worker receipt can qualify against that actual prior.
  let baseline = collectedNativeFixture()
  let fixture = baseline.fixture
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  var path = "application-managed-supplied-chain.json"
  let original = startLogicalServices(owner, fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let before = owner.stateSnapshot.value
  let blockOwner = fixture.first.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let ticket = beginManagedCurrent(owner, input, currentWire(blockOwner),
      fixture.first.source.older, currentCandidateLimits())
  owner.waitManagedPreparation()
  let receipt = owner.collectPreparation(ticket)
  let declarations = successorDeclarations(receipt.currentValue.value, fixture.first.services)
  let plan = owner.planCollectedSupplied(receipt, collectedSuppliedTestLimits())
  assert plan.error == CollectedSuppliedPlanError.None
  let logical = owner.executeCollectedSupplied(plan.value, declarations)
  assert logical.error == CollectedSuppliedError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, before)
  assert owner.enqueueCurrentAccumulation(receipt.currentValue.value) ==
      CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.takeCurrentAccumulation.error == CurrentHandoffError.None
  assert owner.executeCollectedSupplied(plan.value, declarations).error ==
      CollectedSuppliedError.StaleUpdate
  assert owner.planCollectedSupplied(receipt, collectedSuppliedTestLimits()).error ==
      CollectedSuppliedPlanError.AdmissionFailure
  owner.close()
  let detached = copySuppliedServices(logical.value.currentLogicalInventory.value, suppliedServicesTestLimits)
  assert detached.error == SuppliedServicesError.None and detached.value.len == 2
  echo "application-managed-supplied: ok"
try:
  main()
except:
  quit(2) # Native lifecycle exceptions cannot be mistaken for complete qualification.
