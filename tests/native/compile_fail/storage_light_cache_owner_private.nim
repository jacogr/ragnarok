# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable cache owners and tagged results expose only checked accessors.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/storage/light_state_cache
let hidden = default(LightStateCache)
discard hidden.data
