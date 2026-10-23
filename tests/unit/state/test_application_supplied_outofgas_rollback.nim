# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A successful funded write followed by unaffordable host work qualifies only the selected rollback namespace.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
    current_namespace_context, current_namespace_transition_context, current_namespace_execution_context,
    accumulation_execution_context,
    current_identity_context, supplied_services_context, pvm_accumulation_program]
import ../../../src/app/[collected_supplied_state, preparation_worker, current_block_input]
import ../../../src/state/[current_identities, current_logical, supplied_logical_inventory,
    supplied_services, accumulation_current_update, store]
import ../../../src/codec/[bounded, state_layout, state_accounts, state_composition,
    state_service_values, state_requests]
import ../../../src/crypto/primitives
proc main() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let value = @[91'u8, 92, 93]
  options.secondProgram = writeMutationCode(value, [registerImmediate(11, 65536), @[10'u8, 5], @[
      50'u8, 0]])
  options.allowanceGas = 3000 # Fund the first write; the later 65536-byte host charge is unaffordable before memory access.
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
  echo "application-supplied-outofgas-rollback: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
