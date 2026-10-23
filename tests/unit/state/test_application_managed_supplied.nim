# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed supplied qualification consumes the actual collected successor and remains separate from adoption and listener lifetime.
import std/[assertions, syncio]
import std/posix/posix
import ../../support/[collected_native_context, collected_supplied_context,
    collected_logical_services_context,

collected_logical_context, accumulation_current_candidate_context, supplied_services_context]
import ../../../src/app/[services, collected_supplied_plan, collected_supplied_state,
    current_block_input, preparation_worker, current_handoff]
import ../../../src/state/[accumulation_current_update, accumulation_round, accumulation_queue,
    report_admission, block_transition, block_admission, current_logical, supplied_services,
    supplied_logical_inventory, store]
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
