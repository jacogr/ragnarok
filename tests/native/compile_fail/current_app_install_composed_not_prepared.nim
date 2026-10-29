# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedChainUpdate but got: PreparedCurrentAccumulationConsensus", "early": ["owner.(installPrepared,", "[2] expected: PreparedChainUpdate but got: PreparedCurrentAccumulationConsensus"]}

## Canonical installation requires current opaque preparation, not just state composition.
import ../../../src/app/chain
import ../../../src/state/accumulation/current/consensus as accumulation_current_consensus
var owner = default(ApplicationChain)
owner.installPrepared(default(PreparedCurrentAccumulationConsensus))
