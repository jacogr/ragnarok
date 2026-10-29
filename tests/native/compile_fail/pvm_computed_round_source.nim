# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare published snapshot cannot replace computed successor authority.

# @@Verification={"group": "nominal", "expected": "ComputedReportSuccessor", "early": ["prepareComputedRound(", "[1] expected: ComputedReportSuccessor but got: StateStoreSnapshot"]}

import ../../../src/state/computed/round as computed_round
import ../../../src/state/store
discard prepareComputedRound(default(StateStoreSnapshot), ComputedRoundConfig())
