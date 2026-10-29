# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "DirectoryServiceIndex", "early": ["directoryServiceAt(", "[2] expected: DirectoryServiceIndex but got: InventoryServiceIndex"]}

## Capture-order coordinates cannot substitute for sorted-directory coordinates.
import ../../../src/state/service/directory as service_directory
import ../../../src/state/inventory
discard directoryServiceAt(default(StateServiceDirectory), InventoryServiceIndex(0))
