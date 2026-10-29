# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Absence ownership and result storage stay private.
import ../../../src/state/accumulation/[absent as accumulation_absent,
    inputs as accumulation_inputs]
import ../../../src/state/store
import ../../../src/codec/header
let refused = finishAbsentAccumulation(default(PreparedAccumulationInputs), InvocationServiceIndex(
    0), default(StateStoreSnapshot), HeaderSlot(0))
discard refused.status
