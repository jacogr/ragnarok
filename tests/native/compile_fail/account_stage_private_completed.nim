# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Phase result storage cannot expose inactive payloads or writable discriminators.
import ../../../src/state/accumulation/account/stage as accumulation_account_stage
import "../../../src/state/accumulation/block/guests" as accumulation_block_guests
let refused = prepareAccumulationAccountStage(default(BlockAccumulationGuests), default(
    AccumulationAccountStageLimits))
discard refused.completed
