# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual forget/restore execution qualifies the exact three-slot retained request history.
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
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let hash = options.signed.serviceNamespaces[1].preimages[1].hash
  options.secondProgram = requestMutationCode(hash, RequestLength(1), [26'u8, 25])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].requests[1].history = reavailableHistory(RequestSlot(1), RequestSlot(2), RequestSlot(2))
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(1), ByteLimit(36)).value
  let fixture = collectMutation(origin, expected, key)
  let logical = qualifyMutation(fixture)
  let supplied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  let history = supplied[1].requests[1].history
  assert history.state == RequestState.Reavailable
  assert uint32(history.originalFrom) == 1 and uint32(history.removedAt) == 2 and uint32(
      history.restoredAt) == 2
  fixture.checkMutationProof(true, @[3'u8, 1, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0])
  var stale = fixture.declarations
  stale[1].requests[1].history = availableHistory(RequestSlot(1))
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), stale).error ==
      CollectedSuppliedError.StateFailure
  echo "application-supplied-request-restoration: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
