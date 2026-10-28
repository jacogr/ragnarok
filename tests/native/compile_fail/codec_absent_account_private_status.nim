# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Absence ownership and result storage stay private.
import ../../../src/state/accumulation_absent as state_accumulation_absent
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/store as state_store
import ../../../src/codec/header as codec_header
let refused = finishAbsentAccumulation(default(PreparedAccumulationInputs), InvocationServiceIndex(
    0), default(StateStoreSnapshot), HeaderSlot(0))
discard refused.status
