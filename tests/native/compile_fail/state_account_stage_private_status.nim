# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Phase result storage cannot expose inactive payloads or writable discriminators.
import ../../../src/state/accumulation_account_stage as state_accumulation_account_stage
import ../../../src/state/accumulation_block_guests as state_accumulation_block_guests
let refused = prepareAccumulationAccountStage(default(BlockAccumulationGuests), default(
    AccumulationAccountStageLimits))
discard refused.status
