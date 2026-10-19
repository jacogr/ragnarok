# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture protecting provision ownership and nominal ordinal/target boundaries.
## Private storage or an unrelated protocol scalar must not forge or select a validated retained provision.

# @@Verification={"group": "nominal", "expected": "AccumulationProvisionIndex", "early": ["effectProvisionAt(", "[2] expected: AccumulationProvisionIndex but got: ServiceIndex"]}

import ../../../src/state/accumulation_effects
import ../../../src/codec/composite
discard effectProvisionAt(default(AccumulationEffectContext), ServiceIndex(42))
