# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reusable phases retain private result payloads independently of authenticated wrappers.
import ../../../src/state/accumulation_account_phase as state_accumulation_account_phase
import ../../../src/state/accumulation_provision_phase as state_accumulation_provision_phase
import ../../../src/state/accumulation_global_phase as state_accumulation_global_phase
import ../../../src/state/accumulation_coverage as state_accumulation_coverage
import ../../../src/state/accumulation_provisions as state_accumulation_provisions
let refused = prepareAccumulationProvisionPhase(default(PreparedAccumulationAccountPhase), default(
    AccumulationProvisionUnionLimits))
discard refused.completed
