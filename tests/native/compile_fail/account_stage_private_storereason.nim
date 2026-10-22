# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "storeReason"}

## Phase result storage cannot expose inactive payloads or writable discriminators.
import ../../../src/state/[accumulation_account_stage, accumulation_block_guests]
let refused = prepareAccumulationAccountStage(default(BlockAccumulationGuests), default(
    AccumulationAccountStageLimits))
discard refused.storeReason
