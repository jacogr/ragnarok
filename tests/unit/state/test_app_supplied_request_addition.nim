# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual funded solicitation qualifies a new request marker with exact requested-state wire bytes.
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
  let hash = ServicePreimageHash(array[32, byte](blake2b256([71'u8, 72]).value))
  options.secondProgram = requestMutationCode(hash, RequestLength(2), [25'u8])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].requests.add(StateRequestItem(hash: hash, length: RequestLength(2),
      history: requestedHistory()))
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(2), ByteLimit(36)).value
  let fixture = collectMutation(origin, expected, key)
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.NewIdentity
  let logical = qualifyMutation(fixture)
  let supplied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert supplied[1].requests.len == 4 and supplied[1].requests[3].history.state ==
      RequestState.Requested
  fixture.checkMutationProof(true, @[0'u8])
  var omitted = fixture.declarations
  omitted[1].requests.setLen(3)
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), omitted).error ==
      CollectedSuppliedError.StateFailure
  echo "application-supplied-request-addition: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
