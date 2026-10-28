# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: InvocationServiceIndex but got: ServiceIndex","early":["finishAbsentAccumulation(","[2] expected: InvocationServiceIndex but got: ServiceIndex"]}

## Absent outcomes cannot alias protocol service ordinals or actual executed outcomes.
import ../../../src/state/accumulation_absent as state_accumulation_absent
import ../../../src/state/accumulation_inputs as state_accumulation_inputs
import ../../../src/state/accumulation_outcome as state_accumulation_outcome
import ../../../src/state/store as state_store
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_accounts as codec_state_accounts
discard finishAbsentAccumulation(default(PreparedAccumulationInputs), ServiceIndex(0), default(
    StateStoreSnapshot), HeaderSlot(0))
