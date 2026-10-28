# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccumulationProvisionSourceIndex", "early": ["provisionSourceAt(", "[2] expected: AccumulationProvisionSourceIndex but got: AccumulationProvisionIndex"]}

## A per-context provision ordinal cannot select a retained union source.

import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/accumulation_effects as state_accumulation_effects
var plan: PreparedAccumulationProvisions
discard provisionSourceAt(plan, AccumulationProvisionIndex(0))
