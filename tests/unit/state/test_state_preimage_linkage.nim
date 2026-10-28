# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete maps prove request-key membership without conflating history, content or resource refusal.
# @@Verification={"arc": "state_preimage_linkage_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_inventory_context
import ../../support/testing_arc_evidence
import ../../../src/state/preimage_linkage as state_preimage_linkage
import ../../../src/state/inventory as state_inventory
import ../../../src/state/manifest as state_manifest
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_requests as codec_state_requests
import ../../../src/codec/state_service_values as codec_state_service_values
include ../../native/nimony_composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all hashes after independent fixture capture.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Prove matching performs no payload hashing or source reconstruction.
const limits = PreimageLinkageLimits(services: ElementLimit(2), preimages: ElementLimit(1),
    comparisons: ElementLimit(1))
proc cycle(source: StateInventory) =
  ## Retire a complete certificate and its retained owner each iteration.
  let checked = auditPreimageLinkage(source, limits).value
  assert checked.linkageInfo.value.preimages == 1
proc main() {.raises.} =
  ## Capture sources that independently vary request membership while retaining complete-map provenance.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services[0].requests[0].length = RequestLength(2)
  let wrongLength = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = inventoryServices()
  var otherHash = array[32, byte](services[0].requests[0].hash)
  otherHash[0] = otherHash[0] xor 255
  services[0].requests[0].hash = ServicePreimageHash(otherHash)
  let wrongHash = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = inventoryServices()
  services[0].requests = @[]
  let absent = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = inventoryServices()
  services[0].requests[0].history = requestedHistory()
  let requested = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = inventoryServices()
  let original = services[0].requests[0]
  services[0].requests[0].length = RequestLength(2)
  services[0].requests.add(original)
  let late = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = inventoryServices()
  services[0].preimages = @[]
  let empty = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  fail(1)
  let result = auditPreimageLinkage(source, limits)
  assert result.error == PreimageLinkageError.None
  assert result.value.linkageInfo.value.preimages == 1 and
      result.value.linkageInfo.value.comparisons == 1
  assert sameStateSnapshot(result.value.linkageInventory.value.inventorySource.value.manifestSource.value,
    source.inventorySource.value.manifestSource.value)
  for bad in [wrongLength, wrongHash, absent]:
    let refused = auditPreimageLinkage(bad, limits)
    assert refused.error == PreimageLinkageError.MissingRequest
    assert uint32(refused.failedService) == 7 and uint64(refused.failedPreimage) ==
        0 # Exact unmatched original location.
  assert auditPreimageLinkage(requested, limits).error == PreimageLinkageError.None
  assert auditPreimageLinkage(late, limits).error == PreimageLinkageError.LimitExceeded
  var extended = limits
  extended.comparisons = ElementLimit(2)
  assert auditPreimageLinkage(late, extended).value.linkageInfo.value.comparisons == 2
  extended = limits
  extended.services = ElementLimit(1)
  assert auditPreimageLinkage(source, extended).error == PreimageLinkageError.LimitExceeded
  extended = limits
  extended.preimages = ElementLimit(0)
  assert auditPreimageLinkage(absent, extended).error == PreimageLinkageError.LimitExceeded
  assert auditPreimageLinkage(empty, PreimageLinkageLimits(services: ElementLimit(
      2))).value.linkageInfo.value.preimages == 0
  assert auditPreimageLinkage(default(StateInventory), limits).error ==
      PreimageLinkageError.InvalidSource
  assert default(CheckedPreimageLinkage).linkageInfo.error == PreimageLinkageError.Uninitialized
  assert default(CheckedPreimageLinkage).linkageInventory.error ==
      PreimageLinkageError.Uninitialized
  assert calls() == 0
  for i in 0..<25: cycle(source) # Warm the exact certificate ownership path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # Completed matching retains no prefix arrays or accumulating owners.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_preimage_linkage", 1000, before, finalBytes)
  fail(0)
  echo "state-preimage-linkage: ok"
try:
  main()
except:
  quit(2) # Fixture errors never masquerade as invariant checks.
