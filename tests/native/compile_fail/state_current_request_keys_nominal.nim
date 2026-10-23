# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Storage ordinals cannot select a physical request key.
# @@Verification={"group":"nominal","expected":"InventoryRequestIndex","early":["currentRequestKeyAt(","[3] expected: InventoryRequestIndex but got: InventoryStorageIndex"]}
import ../../../src/state/[current_request_keys, inventory]
discard currentRequestKeyAt(default(CurrentRequestKeys), InventoryServiceIndex(0),
    InventoryStorageIndex(0))
