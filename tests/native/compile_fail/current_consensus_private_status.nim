# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Current composed-state proof representation stays private.
import ../../../src/state/accumulation/current/consensus as accumulation_current_consensus
import ../../../src/state/accumulation/consensus as accumulation_consensus
import ../../../src/state/accumulation/current/authorization as accumulation_current_authorization
let refused = prepareCurrentAccumulationConsensus(default(PreparedCurrentAccumulationAuthorization),
    default(AccumulationConsensusLimits))
discard refused.status
