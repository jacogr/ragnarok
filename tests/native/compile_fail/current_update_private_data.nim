# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## The retained immutable candidate graph is private.
import ../../../src/state/accumulation_current_update
let owner = default(PreparedCurrentChainUpdate)
discard owner.data
