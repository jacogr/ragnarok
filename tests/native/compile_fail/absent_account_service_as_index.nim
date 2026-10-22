# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: InvocationServiceIndex but got: ServiceIndex","early":["finishAbsentAccumulation(","[2] expected: InvocationServiceIndex but got: ServiceIndex"]}

## Absent outcomes cannot alias protocol service ordinals or actual executed outcomes.
import ../../../src/state/[accumulation_absent, accumulation_inputs, accumulation_outcome, store]
import ../../../src/codec/[header, state_accounts]
discard finishAbsentAccumulation(default(PreparedAccumulationInputs), ServiceIndex(0), default(
    StateStoreSnapshot), HeaderSlot(0))
