# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: ByteLimit but got: AccumulationCompositionLimits", "early": ["owner.(prepareAccumulation,", "[3] expected: ByteLimit but got: AccumulationCompositionLimits"]}

## Current preparation cannot silently select legacy recomposition policy.
import ../../../src/app/chain
import ../../../src/state/accumulation/current/consensus as accumulation_current_consensus
import ../../../src/state/accumulation/completion as accumulation_completion
var owner = default(ApplicationChain)
discard owner.prepareAccumulation(source = default(PreparedCurrentAccumulationConsensus),
    headerBytes = default(AccumulationCompositionLimits))
