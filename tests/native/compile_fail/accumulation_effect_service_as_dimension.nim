# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Compiler rejection probe for private accumulation effect storage and nominal mutation arguments.
## This access/call must fail rather than forge implication state or substitute an unrelated protocol hash.

# @@Verification={"group": "nominal", "expected": "AccumulationDimension", "early": ["effectContext(", "[2] expected: AccumulationDimension but got: ServiceIndex"]}

import ../../../src/state/accumulation/effects as accumulation_effects
import ../../../src/codec/composite
discard effectContext(default(AccumulationEffects), ServiceIndex(42))
