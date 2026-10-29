# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot owners and result alternatives expose only selected guarded accessors.
# @@Verification={"group": "privacy", "expected": "owner"}
import ../../../src/storage/light/snapshot as light_snapshot
let hidden = default(PreparedLightSnapshot)
discard hidden.owner
