# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/failed application operations cannot expose or forge a successful partial snapshot.
# @@Verification={"group":"privacy","expected":"completed"}
import ../../../src/app/light/store as light_store
let outcome = default(LightStoreResult[LightStorageSnapshot])
discard outcome.completed
