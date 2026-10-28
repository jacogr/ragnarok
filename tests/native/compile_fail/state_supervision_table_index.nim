# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "InventoryServiceIndex", "early": ["supervisionTableAt(", "[2] expected: InventoryServiceIndex but got: DirectoryServiceIndex"]}

## Sorted-directory ordinals cannot select original-order batch rows.
import ../../../src/state/supervision_table as state_supervision_table
import ../../../src/state/service_directory as state_service_directory
discard supervisionTableAt(default(StateSupervisionTable), DirectoryServiceIndex(0))
