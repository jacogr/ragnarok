# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal Blake2b-256 content, malformed complete maps and observer budgets qualify source-bound content checks.
# @@Verification={"arc": "state_preimage_content_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, arc_evidence]
import ../../../src/state/[preimage_content, inventory, manifest, store]
import ../../../src/codec/bounded
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset counters and optionally reject all primitive hash calls.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe zero-hash preflight and exactly one content hash independently.
const limits = PreimageContentLimits(services: ElementLimit(2), preimages: ElementLimit(1),
  perValue: ByteLimit(3), totalBytes: ByteLimit(3))
proc cycle(source: StateInventory) =
  ## Retire detached payloads, results and retained source handles each iteration.
  let result = auditPreimageContent(source, limits)
  assert result.error == PreimageContentError.None
  assert result.value.contentInfo.value.bytes == 3
proc main() {.raises.} =
  ## Capture independent complete maps before measuring only content validation calls.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services[0].preimages[0].value[0] = 98
  let wrong = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  services = inventoryServices()
  services[0].preimages = @[]
  let empty = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  fail(0)
  let result = auditPreimageContent(source, limits)
  assert result.error == PreimageContentError.None and calls() == 1
  assert result.value.contentInfo.value.preimages == 1 and result.value.contentInfo.value.bytes == 3
  assert sameStateSnapshot(result.value.contentInventory.value.inventorySource.value.manifestSource.value,
    source.inventorySource.value.manifestSource.value)
  fail(0)
  let mismatch = auditPreimageContent(wrong, limits)
  assert mismatch.error == PreimageContentError.HashMismatch and calls() == 1
  assert uint32(mismatch.failedService) == 7 and uint64(mismatch.failedPreimage) == 0
  fail(1)
  var short = limits
  short.services = ElementLimit(1)
  assert auditPreimageContent(source, short).error == PreimageContentError.LimitExceeded
  short = limits
  short.preimages = ElementLimit(0)
  assert auditPreimageContent(source, short).error == PreimageContentError.LimitExceeded
  short = limits
  short.perValue = ByteLimit(2)
  assert auditPreimageContent(source, short).error == PreimageContentError.LimitExceeded
  short = limits
  short.totalBytes = ByteLimit(2)
  assert auditPreimageContent(wrong, short).error == PreimageContentError.LimitExceeded
  assert calls() == 0
  assert auditPreimageContent(empty, PreimageContentLimits(services: ElementLimit(
      2))).value.contentInfo.value.preimages == 0
  assert calls() == 0
  let refused = auditPreimageContent(source, limits)
  assert refused.error == PreimageContentError.BackendFailure and calls() == 1
  assert uint32(refused.failedService) == 7 and uint64(refused.failedPreimage) == 0
  assert auditPreimageContent(default(StateInventory), limits).error ==
      PreimageContentError.InvalidSource
  assert default(CheckedPreimageContent).contentInfo.error == PreimageContentError.Uninitialized
  assert default(CheckedPreimageContent).contentInventory.error ==
      PreimageContentError.Uninitialized
  fail(0)
  for i in 0..<25: cycle(source) # Warm the exact allocation and hash path before measuring retirements.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # Copied payloads and successful certificate handles retire together.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes
  recordArcRelease("state_preimage_content", 1000, before, finalBytes)
  echo "state-preimage-content: ok"
try:
  main()
except:
  quit(2) # Fixture/setup refusal cannot satisfy content or ARC evidence.
