# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Request-history slots cannot silently become refinement lookup anchors.

# @@Verification={"group": "nominal", "expected": "LookupSlot", "early": ["captureHistoricalLookup(", "[3] expected: LookupSlot but got: RequestSlot"]}

import ../../../src/state/refinement/lookup as refinement_lookup
import ../../../src/state/store
import ../../../src/codec/composite
import ../../../src/codec/state/requests as state_requests
discard captureHistoricalLookup(default(StateStoreSnapshot), ServiceIndex(42), RequestSlot(0))
