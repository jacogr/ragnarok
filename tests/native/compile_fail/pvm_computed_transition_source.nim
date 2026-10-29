# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached or mutable inputs as completed transition authority.

# @@Verification={"group": "nominal", "expected": "ConfiguredComputedReport", "early": ["bindComputedTransition(", "[1] expected: ConfiguredComputedReport but got: LookupAnchoredComputedReport"]}

import ../../../src/state/computed/[transition as computed_transition, profile as computed_profile,
    lookup as computed_lookup]
import "../../../src/state/block/transition" as block_transition
import ../../../src/state/store
import ../../../src/codec/bounded
discard bindComputedTransition(default(LookupAnchoredComputedReport), default(
    BlockTransitionResult), ByteLimit(4096))
