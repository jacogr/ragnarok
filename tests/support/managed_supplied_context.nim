# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reusable actual managed current collection and complete supplied qualification for original logical consumers.
import std/assertions
import ./[current_repeated_logical_context, collected_native_context, collected_logical_context,
    collected_logical_services_context, collected_supplied_context, accumulation_current_candidate_context]
import ../../src/app/services
import "../../src/app/current/block/input" as current_block_input
import ../../src/app/preparation_worker
import ../../src/app/collected/supplied/[plan as collected_supplied_plan,
    state as collected_supplied_state]
import ../../src/state/current/logical as current_logical
import ../../src/state/accumulation/[round as accumulation_round, queue as accumulation_queue]
import ../../src/state/report/admission as report_admission
import "../../src/state/block/transition" as block_transition
import "../../src/state/block/admission" as block_admission
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
