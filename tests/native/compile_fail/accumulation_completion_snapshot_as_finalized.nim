# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedFinalAccumulation", "early": ["prepareAccumulationComposition(", "[1] expected: PreparedFinalAccumulation but got: StateStoreSnapshot"]}

## A detached complete-map snapshot cannot substitute authenticated finalized execution ownership.

import ../../../src/state/[accumulation_completion, store]

discard prepareAccumulationComposition(default(StateStoreSnapshot), default(AccumulationCompositionLimits))
