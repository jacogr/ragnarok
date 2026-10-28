# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private installed-child authority and selected result storage.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/assured_chain as state_assured_chain
var candidate: AssuredChainResult[AdvancedAssuredChain]
discard candidate.completed
