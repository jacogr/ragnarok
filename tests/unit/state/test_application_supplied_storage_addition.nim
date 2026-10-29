# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine new raw storage identities qualify from complete supplied successor declarations and authenticate under the actual posterior root.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
    current_namespace_context, current_namespace_transition_context,
    current_namespace_execution_context,
    accumulation_execution_context,
    current_identity_context, supplied_services_context]
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
    composition as state_composition, service_values as state_service_values]
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
