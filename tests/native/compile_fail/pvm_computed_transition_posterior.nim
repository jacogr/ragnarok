# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached or mutable inputs as completed transition authority.

# @@Verification={"group": "nominal", "expected": "BlockTransitionResult", "early": ["bindComputedTransition(", "[2] expected: BlockTransitionResult but got: StateStoreSnapshot"]}

import ../../../src/state/computed_transition as state_computed_transition
import ../../../src/state/computed_profile as state_computed_profile
import ../../../src/state/computed_lookup as state_computed_lookup
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
discard bindComputedTransition(default(ConfiguredComputedReport), default(StateStoreSnapshot),
    ByteLimit(4096))
