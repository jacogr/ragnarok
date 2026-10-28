# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Request-history slots cannot silently become refinement lookup anchors.

# @@Verification={"group": "nominal", "expected": "LookupSlot", "early": ["captureHistoricalLookup(", "[3] expected: LookupSlot but got: RequestSlot"]}

import ../../../src/state/refinement_lookup as state_refinement_lookup
import ../../../src/state/store as state_store
import ../../../src/codec/composite as codec_composite
import ../../../src/codec/state_requests as codec_state_requests
discard captureHistoricalLookup(default(StateStoreSnapshot), ServiceIndex(42), RequestSlot(0))
