# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot mutate a successful inventory's owned identities.
# @@Verification={"group":"privacy","expected":"queries"}
import ../../../src/storage/paged_stream as storage_paged_stream
let inventory = default(PagedQueryInventory)
discard inventory.queries
