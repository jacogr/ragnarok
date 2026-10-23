# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine new raw storage identities qualify from complete supplied successor declarations and authenticate under the actual posterior root.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
    current_namespace_context, current_namespace_transition_context,
    current_namespace_execution_context,
    accumulation_execution_context,
    current_identity_context, supplied_services_context]
import ../../../src/app/[collected_supplied_state, preparation_worker, current_block_input]
import ../../../src/state/[current_identities, current_logical, supplied_logical_inventory,
    supplied_services, accumulation_current_update, store]
import ../../../src/codec/[bounded, state_layout, state_accounts, state_composition, state_service_values]
proc main() {.raises.} =
  ## Service99 is funded before signatures; its real host write creates raw key7 while every untouched raw identity remains explicitly supplied.
  let value = @[91'u8, 92, 93]
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = namespaceStorageCode(value)
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].storage.add(StateStorageItem(key: @[7'u8], value: value))
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  assert fixture.receipt.currentValue.value.currentUpdatePriorState.lookup(key).error ==
      StateStoreError.MissingKey
  let refusal = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refusal.error == CurrentIdentityError.NewIdentity
  let logical = qualifyMutation(fixture)
  let copied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert copied[1].storage.len == 3
  assert uint32(copied[1].metadata.storageItems) == 9
  fixture.checkMutationProof(true, value)
  var omitted = fixture.declarations
  omitted[1].storage.setLen(2)
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), omitted).error ==
      CollectedSuppliedError.StateFailure
  assert copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value[1].storage.len == 3
  echo "application-supplied-storage-addition: ok"
try:
  main()
except:
  quit(2) # A new supplied key alone never grants complete producer provenance or qualification.
