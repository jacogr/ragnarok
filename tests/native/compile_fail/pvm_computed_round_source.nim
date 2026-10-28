# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare published snapshot cannot replace computed successor authority.

# @@Verification={"group": "nominal", "expected": "ComputedReportSuccessor", "early": ["prepareComputedRound(", "[1] expected: ComputedReportSuccessor but got: StateStoreSnapshot"]}

import ../../../src/state/computed_round as state_computed_round
import ../../../src/state/store as state_store
discard prepareComputedRound(default(StateStoreSnapshot), ComputedRoundConfig())
