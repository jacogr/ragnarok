# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private installed-child authority and selected result storage.

# @@Verification={"group": "privacy", "expected": "headerReason"}

import ../../../src/state/assured_chain
var candidate: AssuredChainResult[AdvancedAssuredChain]
discard candidate.headerReason
