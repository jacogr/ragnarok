# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection probe for private accumulation effect storage and nominal mutation arguments.
## This access/call must fail rather than forge implication state or substitute an unrelated protocol hash.

# @@Verification={"group": "nominal", "expected": "OutputCommitment", "early": ["recordAccumulationYield(", "[2] expected: OutputCommitment but got: StateRoot"]}

import ../../../src/state/accumulation_effects
import ../../../src/codec/state_trie
discard recordAccumulationYield(default(AccumulationEffects), default(StateRoot))
