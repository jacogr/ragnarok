# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Detached compact inventory cannot substitute original full selected-view provenance.
# @@Verification={"group":"nominal","expected":"SelectedLogicalParent","early":["preserveCurrentIdentities(","[1] expected: SelectedLogicalParent but got: SuppliedLogicalInventory"]}
import ../../../src/state/[current_identities, supplied_logical_inventory, accumulation_current_update]
discard preserveCurrentIdentities(default(SuppliedLogicalInventory), default(
    PreparedCurrentChainUpdate), CurrentIdentityLimits())
