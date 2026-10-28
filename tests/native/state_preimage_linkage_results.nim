# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime payload/location extraction guards retain a genuine independent linkage control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_inventory_context
import ../../src/state/preimage_linkage as state_preimage_linkage
import ../../src/state/inventory as state_inventory
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_accounts as codec_state_accounts
include nimony_composition_fixture
proc extract(outcome: PreimageLinkageResult[CheckedPreimageLinkage]): CheckedPreimageLinkage {.noinline.} =
  ## Keep default and actual invalid-source extraction dynamic.
  outcome.value
proc offender(outcome: PreimageLinkageResult[CheckedPreimageLinkage]): ServiceIndex {.noinline.} =
  ## Defaults and resource refusals have no association account.
  outcome.failedService
proc location(outcome: PreimageLinkageResult[CheckedPreimageLinkage]): InventoryPreimageIndex {.noinline.} =
  ## Defaults and resource refusals have no association coordinate.
  outcome.failedPreimage
case paramStr(1)
of "default": discard extract(default(PreimageLinkageResult[CheckedPreimageLinkage])) # No default certificate.
of "offender": discard offender(default(PreimageLinkageResult[CheckedPreimageLinkage])) # No default account.
of "ordinal": discard location(default(PreimageLinkageResult[CheckedPreimageLinkage])) # No default coordinate.
of "source": discard extract(auditPreimageLinkage(default(StateInventory), PreimageLinkageLimits())) # Actual refusal.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let checked = extract(auditPreimageLinkage(source, PreimageLinkageLimits(services: ElementLimit(
      2), preimages: ElementLimit(1), comparisons: ElementLimit(1))))
  assert checked.linkageInfo.value.comparisons == 1
  echo "state-preimage-linkage-results: ok"
else: quit(2) # Unknown selectors never pass controls.
