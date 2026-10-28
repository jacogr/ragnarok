# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Caller cannot forge selected economic configuration or mutate private alternatives.
import ../../../src/state/economic_profile as state_economic_profile
var value = default(EconomicProfileResult[StateEconomicProfile])
discard value.status
