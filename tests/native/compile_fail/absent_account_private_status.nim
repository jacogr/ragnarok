# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Absence ownership and result storage stay private.
import ../../../src/state/[accumulation_absent, accumulation_inputs, store]
import ../../../src/codec/header
let refused = finishAbsentAccumulation(default(PreparedAccumulationInputs), InvocationServiceIndex(
    0), default(StateStoreSnapshot), HeaderSlot(0))
discard refused.status
