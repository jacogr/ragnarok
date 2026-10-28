# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare captured block cannot replace original computed predecessor authority.

# @@Verification={"group": "nominal", "expected": "AdvancedComputedChain", "early": ["prepareComputedAssurances(", "[1] expected: AdvancedComputedChain but got: BlockSnapshot"]}

import ../../../src/state/computed_assurances as state_computed_assurances
import ../../../src/chain/genesis as chain_genesis
import ../../../src/codec/block_codec as codec_block_codec
discard prepareComputedAssurances(default(BlockSnapshot), default(OwnedBlock),
    ComputedAssuranceConfig())
