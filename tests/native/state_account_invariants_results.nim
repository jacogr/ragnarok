# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic joined-payload guards preserve genuine evidence as the positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_inventory_context
import ../support/codec_account_invariant_context
import ../../src/state/account_invariants as state_account_invariants
import ../../src/state/inventory as state_inventory
import ../../src/state/footprint_audit as state_footprint_audit
import ../../src/state/preimage_content as state_preimage_content
import ../../src/state/preimage_linkage as state_preimage_linkage
include nimony_composition_fixture
proc extract(outcome: AccountInvariantResult[CheckedAccountInvariants]): CheckedAccountInvariants {.noinline.} =
  ## Default and failed joins cannot expose a retained complete source.
  outcome.value
case paramStr(1)
of "default": discard extract(default(AccountInvariantResult[
    CheckedAccountInvariants])) # Default carries no payload.
of "invalid": discard extract(joinAccountInvariants(default(CheckedAccountFootprints), default(
    CheckedPreimageContent), default(CheckedPreimageLinkage))) # Actual invalid input carries no prefix.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let checked = extract(joinAccountInvariants(auditAccountFootprints(source,
      invariantFootprintLimits).value,
    auditPreimageContent(source, invariantContentLimits).value, auditPreimageLinkage(source,
        invariantLinkageLimits).value))
  assert checked.accountInvariantInfo.value.content.bytes == 3
  echo "state-account-invariants-results: ok"
else: quit(2) # Unknown selectors cannot grant successful controls.
