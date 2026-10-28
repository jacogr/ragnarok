# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual junior service ejection qualifies a reduced complete service inventory and proves account absence.
import std/assertions
import std/syncio
import ../../support/app_collected_native_context
import ../../support/app_collected_mutation_context
import ../../support/state_current_namespace_context
import ../../support/state_current_namespace_transition_context
import ../../support/state_current_namespace_execution_context
import ../../support/state_accumulation_execution_context
import ../../support/state_current_identity_context
import ../../support/state_supplied_services_context
import ../../support/pvm_accumulation_program
import ../../support/codec_service_namespace_seed
import ../../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_service_values as codec_state_service_values
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/crypto/primitives as crypto_primitives
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
