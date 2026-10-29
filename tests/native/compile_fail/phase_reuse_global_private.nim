# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reusable phases retain private result payloads independently of authenticated wrappers.
import ../../../src/state/accumulation/account/phase as accumulation_account_phase
import ../../../src/state/accumulation/provision/phase as accumulation_provision_phase
import ../../../src/state/accumulation/global/phase as accumulation_global_phase
import ../../../src/state/accumulation/[coverage as accumulation_coverage,
    provisions as accumulation_provisions]
let refused = prepareAccumulationGlobalPhase(default(PreparedAccumulationProvisionPhase), default(
    AccumulationGlobalPhaseLimits))
discard refused.completed
