# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable light snapshots expose no mutable cache or proof backing storage.
# @@Verification={"group":"privacy","expected":"data"}
import ../../../src/app/light_store as app_light_store
let snapshot = default(LightStorageSnapshot)
discard snapshot.data
