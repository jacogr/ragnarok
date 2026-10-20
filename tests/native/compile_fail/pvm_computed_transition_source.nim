# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached or mutable inputs as completed transition authority.

# @@Verification={"group": "nominal", "expected": "ConfiguredComputedReport", "early": ["bindComputedTransition(", "[1] expected: ConfiguredComputedReport but got: LookupAnchoredComputedReport"]}

import ../../../src/state/[computed_transition, computed_profile, computed_lookup, block_transition, store]
import ../../../src/codec/bounded
discard bindComputedTransition(default(LookupAnchoredComputedReport), default(
    BlockTransitionResult), ByteLimit(4096))
