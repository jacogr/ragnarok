# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Union source/value owners are private.

import ../../../src/state/accumulation_provisions as state_accumulation_provisions
var plan: PreparedAccumulationProvisions
discard plan.data
