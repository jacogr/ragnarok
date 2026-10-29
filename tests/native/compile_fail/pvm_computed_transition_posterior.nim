# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached or mutable inputs as completed transition authority.

# @@Verification={"group": "nominal", "expected": "BlockTransitionResult", "early": ["bindComputedTransition(", "[2] expected: BlockTransitionResult but got: StateStoreSnapshot"]}

import ../../../src/state/computed/[transition as computed_transition, profile as computed_profile,
    lookup as computed_lookup]
import "../../../src/state/block/transition" as block_transition
import ../../../src/state/store
import ../../../src/codec/bounded
discard bindComputedTransition(default(ConfiguredComputedReport), default(StateStoreSnapshot),
    ByteLimit(4096))
