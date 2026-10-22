# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime payload/location extraction guards retain a genuine independent content control.
import std/[assertions, cmdline, syncio]
import ../support/state_inventory_context
import ../../src/state/[preimage_content, inventory]
import ../../src/codec/[bounded, state_accounts]
include composition_fixture
proc extract(outcome: PreimageContentResult[CheckedPreimageContent]): CheckedPreimageContent {.noinline.} =
  ## Keep default and actual invalid-source extraction dynamic.
  outcome.value
proc offender(outcome: PreimageContentResult[CheckedPreimageContent]): ServiceIndex {.noinline.} =
  ## Defaults and resource refusals have no hash-attempt account.
  outcome.failedService
proc location(outcome: PreimageContentResult[CheckedPreimageContent]): InventoryPreimageIndex {.noinline.} =
  ## Defaults and resource refusals have no hash-attempt coordinate.
  outcome.failedPreimage
case paramStr(1)
of "default": discard extract(default(PreimageContentResult[CheckedPreimageContent])) # No default certificate.
of "offender": discard offender(default(PreimageContentResult[CheckedPreimageContent])) # No default account.
of "ordinal": discard location(default(PreimageContentResult[CheckedPreimageContent])) # No default coordinate.
of "source": discard extract(auditPreimageContent(default(StateInventory), PreimageContentLimits())) # Actual refusal.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let checked = extract(auditPreimageContent(source, PreimageContentLimits(services: ElementLimit(
      2), preimages: ElementLimit(1), perValue: ByteLimit(3), totalBytes: ByteLimit(3))))
  assert checked.contentInfo.value.bytes == 3
  echo "state-preimage-content-results: ok"
else: quit(2) # Unknown selectors never pass controls.
