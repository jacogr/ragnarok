# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Finalized certificates require guarded extraction rather than direct payload access.
# @@Verification={"group": "privacy", "expected": "completed"}

import "../../../src/app/current/block/input" as current_block_input
var owner = default(CurrentBlockInputResult)
discard owner.completed
