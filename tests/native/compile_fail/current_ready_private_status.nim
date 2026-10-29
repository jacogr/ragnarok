# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Current ready proof representation stays private.
import ../../../src/state/accumulation/current/ready as accumulation_current_ready
import ../../../src/state/accumulation/ready as accumulation_ready
import ../../../src/state/accumulation/current/finalization as accumulation_current_finalization
let refused = prepareCurrentAccumulationReady(default(PreparedCurrentAccumulationFinalization),
    default(AccumulationReadyConfig))
discard refused.status
