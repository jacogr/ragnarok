# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Request-history slots cannot silently become refinement lookup anchors.

# @@Verification={"group": "nominal", "expected": "LookupSlot", "early": ["captureHistoricalLookup(", "[3] expected: LookupSlot but got: RequestSlot"]}

import ../../../src/state/[refinement_lookup, store]
import ../../../src/codec/[composite, state_requests]
discard captureHistoricalLookup(default(StateStoreSnapshot), ServiceIndex(42), RequestSlot(0))
