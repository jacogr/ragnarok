# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture protecting provision ownership and nominal ordinal/target boundaries.
## Private storage or an unrelated protocol scalar must not forge or select a validated retained provision.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/accumulation/effects as accumulation_effects
let owner = default(AccumulationProvision)
discard owner.data
