# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual junior service ejection qualifies a reduced complete service inventory and proves account absence.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
    current_namespace_context, current_namespace_transition_context,
    current_namespace_execution_context,
    accumulation_execution_context,
    current_identity_context, supplied_services_context, pvm_accumulation_program, service_namespace_seed]
import ../../../src/app/[collected_supplied_state, preparation_worker, current_block_input]
import ../../../src/state/[current_identities, current_logical, supplied_logical_inventory,
    supplied_services, accumulation_current_update, store]
import ../../../src/codec/[bounded, state_layout, state_accounts, state_composition,
    state_service_values, state_requests]
import ../../../src/crypto/primitives
proc main() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceEjectCode()
  options.secondProgram = namespaceHaltCode()
  options.second = ExecutionEnding.Missing
  options.secondBalance = 0
  options.secondSupervisor = 42
  let initial = namespaceSeeds()
  options.signed.serviceNamespaces = @[initial[0], ServiceNamespaceSeed(service: ServiceIndex(99),
      storage: @[], preimages: @[], requests: @[])]
  let origin = namespaceTransitionFixture(nativeBase(), options, ElementLimit(1))
  var expected = origin.services
  expected.setLen(1)
  let key = chapterServiceKey(StateChapter(255), ServiceIndex(99))
  let fixture = collectMutation(origin, expected, key, ElementLimit(1))
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.MissingIdentity
  let logical = qualifyMutation(fixture)
  let supplied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert supplied.len == 1 and uint32(supplied[0].service) == 42
  fixture.checkMutationProof(false, @[])
  var stale = fixture.declarations
  stale.add(origin.services[1])
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), stale).error ==
      CollectedSuppliedError.StateFailure
  echo "application-supplied-service-ejection: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
