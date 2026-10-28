# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reusable actual managed current collection and complete supplied qualification for original logical consumers.
import std/assertions
import ./state_current_repeated_logical_context
import ./app_collected_native_context
import ./app_collected_logical_context
import ./app_collected_logical_services_context
import ./app_collected_supplied_context
import ./state_accumulation_current_candidate_context
import ../../src/app/services as app_services
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../src/state/current_logical as state_current_logical
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
proc collectManagedSupplied*(owner: var Services, input: var CurrentBlockInput,
    fixture: CurrentRepeatedLogicalFixture): CurrentLogicalState {.raises.} =
  ## All raw identities remain explicitly supplied; canonical owner and receipt come from actual Services execution and collection.
  let blockOwner = fixture.first.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  let ticket = beginManagedCurrent(owner, input, currentWire(blockOwner),
      fixture.first.source.older, currentCandidateLimits())
  owner.waitManagedPreparation()
  let receipt = owner.collectPreparation(ticket)
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  let declarations = successorDeclarations(receipt.currentValue.value, fixture.first.services)
  let plan = owner.planCollectedSupplied(receipt, collectedSuppliedTestLimits()).value
  owner.executeCollectedSupplied(plan, declarations).value
