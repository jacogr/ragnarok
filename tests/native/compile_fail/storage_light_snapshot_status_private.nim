# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot owners and result alternatives expose only selected guarded accessors.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/storage/light_snapshot as storage_light_snapshot
let hidden = default(LightSnapshotResult[PreparedLightSnapshot])
discard hidden.status
