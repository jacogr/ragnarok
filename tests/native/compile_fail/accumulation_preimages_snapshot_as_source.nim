# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationActivity", "early": ["prepareAccumulationPreimages(", "[1] expected: PreparedAccumulationActivity but got: StateStoreSnapshot"]}

## Detached admission or complete state cannot replace the authenticated activity source.

import ../../../src/state/[accumulation_preimages, store]
var source: StateStoreSnapshot
var limits: AccumulationPreimageLimits
discard prepareAccumulationPreimages(source, limits)
