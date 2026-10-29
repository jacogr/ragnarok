# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Inactive provision phase alternatives and their writable tags remain private.
import ../../../src/state/accumulation/provision/stage as accumulation_provision_stage
import ../../../src/state/accumulation/provisions as accumulation_provisions
import ../../../src/state/accumulation/account/stage as accumulation_account_stage
let refused = prepareAccumulationProvisionStage(default(PreparedAccumulationAccountStage), default(
    AccumulationProvisionUnionLimits))
discard refused.completed
