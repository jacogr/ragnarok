# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private installed-child authority and selected result storage.

# @@Verification={"group": "privacy", "expected": "captureReason"}

import ../../../src/state/assured/chain as assured_chain
var candidate: AssuredChainResult[AdvancedAssuredChain]
discard candidate.captureReason
