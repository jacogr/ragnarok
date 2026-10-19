# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CodeHash", "early": ["recordAccumulationUpgrade(", "[2] expected: CodeHash but got: StateRoot"]}

## Reject a state commitment substituted for an offered service-code identity.

import ../../../src/state/accumulation_effects
import ../../../src/codec/[state_trie, state_accounts]
discard recordAccumulationUpgrade(default(AccumulationEffects), default(StateRoot), Gas(0), Gas(0))
