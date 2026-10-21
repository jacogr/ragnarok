# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default disk results cannot expose a partial state snapshot.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/state/[store, disk_store]
let outcome = default(DiskStoreResult[StateStoreSnapshot])
discard outcome.completed
