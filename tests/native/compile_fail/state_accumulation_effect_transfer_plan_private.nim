# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Reject access to a prepared transfer's private immutable plan backing.

import ../../../src/state/accumulation_effects as state_accumulation_effects
let plan = default(PreparedAccumulationTransfer)
discard plan.data
