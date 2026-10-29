# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compilation fixture protecting the nominal context-dimension selector.
## A service identifier cannot select a regular/exceptional tuple position.

# @@Verification={"group": "nominal", "expected": "AccumulationDimension", "early": ["initialContext(", "[2] expected: AccumulationDimension but got: ServiceIndex"]}

import ../../../src/state/accumulation/context as accumulation_context
import ../../../src/codec/composite
discard initialContext(default(PreparedAccumulationContexts), ServiceIndex(0))
