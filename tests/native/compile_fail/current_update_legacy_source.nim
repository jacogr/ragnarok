# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationConsensus but got: PreparedAccumulationConsensus", "early": ["prepareCurrentChainUpdate(", "[3] expected: PreparedCurrentAccumulationConsensus but got: PreparedAccumulationConsensus"]}

## Preparation requires current composed ownership.
import ../../../src/chain/provider
import ../../../src/codec/bounded
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/accumulation/consensus as accumulation_consensus
import ../../../src/state/store
var state = default(StateStore)
var view = default(ChainView)
discard prepareCurrentChainUpdate(state, view, default(PreparedAccumulationConsensus), ByteLimit(0))
