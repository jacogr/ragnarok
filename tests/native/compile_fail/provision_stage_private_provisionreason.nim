# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "provisionReason"}

## Inactive provision phase alternatives and their writable tags remain private.
import ../../../src/state/[accumulation_provision_stage, accumulation_provisions,
    accumulation_account_stage]
let refused = prepareAccumulationProvisionStage(default(PreparedAccumulationAccountStage), default(
    AccumulationProvisionUnionLimits))
discard refused.provisionReason
