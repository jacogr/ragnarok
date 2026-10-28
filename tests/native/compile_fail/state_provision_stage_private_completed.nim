# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Inactive provision phase alternatives and their writable tags remain private.
import ../../../src/state/accumulation_provision_stage as state_accumulation_provision_stage
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../../src/state/accumulation_account_stage as state_accumulation_account_stage
let refused = prepareAccumulationProvisionStage(default(PreparedAccumulationAccountStage), default(
    AccumulationProvisionUnionLimits))
discard refused.completed
