# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Advisory retention plans expose no mutable internal choices or ready flag.
# @@Verification={"group": "privacy", "expected": "removed"}
import ../../../src/storage/light/snapshot as light_snapshot
let hidden = default(LightRetentionPlan)
discard hidden.removed
