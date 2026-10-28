# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "PreparedAccumulationActivity", "early": ["prepareAccumulationPreimages(", "[1] expected: PreparedAccumulationActivity but got: AdmittedPreimages"]}

## Detached admission or complete state cannot replace the authenticated activity source.

import ../../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../../src/state/preimages as state_preimages
var source: AdmittedPreimages
var limits: AccumulationPreimageLimits
discard prepareAccumulationPreimages(source, limits)
