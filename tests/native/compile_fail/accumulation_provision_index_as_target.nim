# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture protecting provision ownership and nominal ordinal/target boundaries.
## Private storage or an unrelated protocol scalar must not forge or select a validated retained provision.

## Verification: {"group": "nominal", "expected": "ServiceIndex", "early": ["recordAccumulationProvision(", "[2] expected: ServiceIndex but got: AccumulationProvisionIndex"]}

import ../../../src/state/accumulation_effects
discard recordAccumulationProvision(default(AccumulationEffects), AccumulationProvisionIndex(0), [],
    default(AccumulationProvisionLimits))
