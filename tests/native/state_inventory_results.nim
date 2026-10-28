# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic compact-inventory payload/reason contracts retain a genuine source-bound positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_inventory_context
import ../../src/state/inventory as state_inventory
import ../../src/state/manifest as state_manifest
import ../../src/codec/state_service_values as codec_state_service_values
include nimony_composition_fixture
proc extract(outcome: StateInventoryResult[StateInventory]): StateInventory {.noinline.} =
  ## Preserve actual linked success assertions for default and refused owners.
  outcome.value
proc keyReason(outcome: StateInventoryResult[StateInventory]): ServiceValueError {.noinline.} =
  ## Key reasons are available only after actual key derivation failure.
  outcome.keyError
proc manifestReason(outcome: StateInventoryResult[
    StateInventory]): StateManifestError {.noinline.} =
  ## Exact-map refusal reasons remain distinct from defaults and key failures.
  outcome.manifestFailure.error
case paramStr(1)
of "value": discard extract(default(StateInventoryResult[StateInventory])) # Default payload refusal.
of "key": discard keyReason(default(StateInventoryResult[StateInventory])) # Inactive key alternative.
of "manifest": discard manifestReason(default(StateInventoryResult[
    StateInventory])) # Inactive source alternative.
of "source":
  let refused = captureStateInventory(default(ValidatedStateManifest), [], inventoryCaptureLimits)
  assert refused.error == StateInventoryError.InvalidSource
  discard extract(refused) # Actual source refusal carries no compact prefix.
of "ok":
  let fixture = compositionFixture(paramStr(2))
  let services = inventoryServices()
  let source = inventoryManifest(fixture, services)
  let captured = extract(captureStateInventory(source, services, inventoryCaptureLimits))
  assert captured.inventoryInfo.value.facts == 5 # Genuine guarded extraction must succeed before accepting runtime misuse verdicts.
  echo "state-inventory-results: ok"
else: quit(2) # Unknown modes never supply successful evidence.
