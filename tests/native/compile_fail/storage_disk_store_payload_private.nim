# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default disk results cannot expose a partial state snapshot.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/state/store as state_store
import ../../../src/state/disk_store as state_disk_store
let outcome = default(DiskStoreResult[StateStoreSnapshot])
discard outcome.completed
