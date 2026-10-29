# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual guest write followed by panic qualifies only the selected original exceptional namespace.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
    current_namespace_context, current_namespace_transition_context,
    current_namespace_execution_context,
    accumulation_execution_context,
    current_identity_context, supplied_services_context, pvm_accumulation_program]
import ../../../src/app/collected/supplied/state as collected_supplied_state
import ../../../src/app/preparation_worker
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/state/current/[identities as current_identities, logical as current_logical]
import ../../../src/state/supplied/[logical_inventory as supplied_logical_inventory,
    services as supplied_services]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, accounts as state_accounts,
    composition as state_composition, service_values as state_service_values,
    requests as state_requests]
import ../../../src/crypto/primitives
proc main() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let value = @[91'u8, 92, 93]
  options.secondProgram = writeMutationCode(value, [@[0'u8]])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  let logical = qualifyMutation(fixture)
  let supplied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert supplied[1].storage.len == 2 and uint32(supplied[1].metadata.storageItems) == 8
  fixture.checkMutationProof(false, @[])
  var unselected = fixture.declarations
  unselected[1].storage.add(StateStorageItem(key: @[7'u8], value: value))
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), unselected).error ==
      CollectedSuppliedError.StateFailure
  echo "application-supplied-panic-rollback: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
