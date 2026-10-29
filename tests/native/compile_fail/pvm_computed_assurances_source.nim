# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare captured block cannot replace original computed predecessor authority.

# @@Verification={"group": "nominal", "expected": "AdvancedComputedChain", "early": ["prepareComputedAssurances(", "[1] expected: AdvancedComputedChain but got: BlockSnapshot"]}

import ../../../src/state/computed/assurances as computed_assurances
import ../../../src/chain/genesis
import ../../../src/codec/block_codec
discard prepareComputedAssurances(default(BlockSnapshot), default(OwnedBlock),
    ComputedAssuranceConfig())
