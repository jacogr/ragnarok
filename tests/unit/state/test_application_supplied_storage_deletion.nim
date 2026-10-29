# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual raw storage deletion qualifies only complete successor declarations and proves absence.
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
  options.secondProgram = namespaceStorageCode(@[])
  options.signed.serviceNamespaces[1].storage[1] = StateStorageItem(key: @[7'u8], value: @[13'u8, 14, 15])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].storage.setLen(1)
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  assert fixture.receipt.currentValue.value.currentUpdatePriorState.lookup(key).value.bytes == @[
      13'u8, 14, 15]
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.MissingIdentity
  let logical = qualifyMutation(fixture)
  let supplied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert supplied[1].storage.len == 1 and uint32(supplied[1].metadata.storageItems) == 7
  fixture.checkMutationProof(false, @[])
  var stale = fixture.declarations
  stale[1].storage.add(StateStorageItem(key: @[7'u8], value: @[13'u8, 14, 15]))
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), stale).error ==
      CollectedSuppliedError.StateFailure
  echo "application-supplied-storage-deletion: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
