# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached or mutable inputs as completed transition authority.

# @@Verification={"group": "nominal", "expected": "BlockTransitionResult", "early": ["bindComputedTransition(", "[2] expected: BlockTransitionResult but got: StateStoreSnapshot"]}

import ../../../src/state/[computed_transition, computed_profile, computed_lookup, block_transition, store]
import ../../../src/codec/bounded
discard bindComputedTransition(default(ConfiguredComputedReport), default(StateStoreSnapshot),
    ByteLimit(4096))
