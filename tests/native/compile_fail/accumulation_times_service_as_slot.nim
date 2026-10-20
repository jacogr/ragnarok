# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AccountSlot", "early": ["projectAccumulationTimes(", "[3] expected: AccountSlot but got: ServiceIndex"]}

## Service identities cannot substitute for absolute account slots.

import ../../../src/state/[accumulation_times, store]
import ../../../src/codec/state_accounts
var state: StateStoreSnapshot
var service: ServiceIndex
var limits: AccumulationTimesLimits
discard projectAccumulationTimes(state, [], service, limits)
