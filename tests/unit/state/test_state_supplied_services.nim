# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Hash-free complete logical declaration reconstruction bounds every descriptor/payload and detaches all mutable outputs.
# @@Verification={"arc": "state_supplied_services_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/codec_supplied_logical_context
import ../../support/state_supplied_services_context
import ../../support/testing_arc_evidence
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_requests as codec_state_requests
include ../../native/nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reconstruction must succeed with the hash backend disabled after complete capture.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## All preflight refusals and full reconstruction must attempt zero hashes.
proc cycle(owner: SuppliedLogicalInventory) =
  ## Retire all detached raw keys, values, preimages and request arrays on each cycle.
  let services = copySuppliedServices(owner, suppliedServicesTestLimits).value
  assert services[0].storage[0].key == @[byte(1), 2]
proc main() {.raises.} =
  ## Independent chapters and explicit child identities produce a complete checked logical owner before projection.
  let services = inventoryServices()
  let source = inventoryManifest(compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE")), services)
  let owner = captureSuppliedLogicalInventory(source, services, suppliedLogicalTestLimits).value
  let emptyOwner = captureSuppliedLogicalInventory(inventoryManifest(compositionFixture(getEnv(
      "RAGNAROK_COMPOSITION_FIXTURE")), []), [], suppliedLogicalTestLimits).value
  var exactBytes = uint64(services.len) * uint64(sizeof(StateService))
  var facts = uint64(services.len)
  for item in services:
    exactBytes += uint64(item.storage.len) * uint64(sizeof(StateStorageItem))
    exactBytes += uint64(item.preimages.len) * uint64(sizeof(StatePreimageItem))
    exactBytes += uint64(item.requests.len) * uint64(sizeof(StateRequestItem))
    facts += uint64(item.storage.len+item.preimages.len+item.requests.len)
    for row in item.storage: exactBytes += uint64(row.key.len+row.value.len)
    for row in item.preimages: exactBytes += uint64(row.value.len)
  let exact = SuppliedServicesLimits(services: ElementLimit(2), facts: ElementLimit(facts),
      perValue: ByteLimit(3), bytes: ByteLimit(exactBytes))
  fail(1)
  let copied = copySuppliedServices(owner, exact)
  assert copied.error == SuppliedServicesError.None
  var output = copied.value
  assert output.len == 2 and output[0].captured.len == 0
  assert output[0].storage[0].key == services[0].storage[0].key
  assert output[0].storage[0].value == services[0].storage[0].value
  assert output[0].preimages[0].value == services[0].preimages[0].value
  assert output[0].requests[0].history.state == RequestState.Available
  output[0].storage[0].key[0] = 9
  output[0].storage[0].value[0] = 9
  output[0].preimages[0].value[0] = 9
  output[0].requests = @[]
  let again = copySuppliedServices(owner, exact).value
  assert again[0].storage[0].key == services[0].storage[0].key
  assert again[0].storage[0].value == services[0].storage[0].value
  assert again[0].preimages[0].value == services[0].preimages[0].value
  assert again[0].requests.len == 1
  for phase in 0..<4:
    var short = exact
    case phase
    of 0: short.services = ElementLimit(1)
    of 1: short.facts = ElementLimit(facts-1)
    of 2: short.perValue = ByteLimit(2)
    else: short.bytes = ByteLimit(exactBytes-1)
    assert copySuppliedServices(owner, short).error == SuppliedServicesError.LimitExceeded
  assert copySuppliedServices(default(SuppliedLogicalInventory), exact).error ==
      SuppliedServicesError.InvalidSource
  assert copySuppliedServices(emptyOwner, SuppliedServicesLimits()).value.len == 0
  assert calls() == 0
  for i in 0..<25: cycle(owner)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(owner)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_supplied_services", 1000, before, finalBytes)
  fail(0)
  assert validateStateManifest(source.manifestGlobals.value, again,
      inventoryManifestLimits).error == StateManifestError.None
  echo "state-supplied-services: ok"
try:
  main()
except:
  quit(2) # Setup/source construction failures cannot qualify detached projection.
