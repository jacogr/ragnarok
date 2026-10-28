# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only selected guarded delta accessors expose authenticated frame authority.
# @@Verification={"group": "privacy", "expected": "owner"}
import ../../../src/storage/light_delta as storage_light_delta
let hidden = default(PreparedLightDelta)
discard hidden.owner
