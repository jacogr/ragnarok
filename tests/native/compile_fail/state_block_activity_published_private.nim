# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## A published successor cannot be fabricated or rebound to a foreign mutable map.

import ../../../src/state/block_activity as state_block_activity
var owner: PublishedBlockActivity
discard owner.data
