# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private computed chain authority and selected-cause storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed/chain as computed_chain
var candidate: AdvancedComputedChain
discard candidate.data
