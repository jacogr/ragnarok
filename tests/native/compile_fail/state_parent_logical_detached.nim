# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "SelectedParentGlobals", "early": ["captureLogicalParent(", "[1] expected: SelectedParentGlobals but got: SuppliedLogicalInventory"]}

## A separately captured raw-key inventory cannot substitute original full-view/profile provenance.
import ../../../src/state/[parent_logical, supplied_logical_inventory]
discard captureLogicalParent(default(SuppliedLogicalInventory), [], SuppliedLogicalLimits())
