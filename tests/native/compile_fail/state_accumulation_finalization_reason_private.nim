# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Reject raw construction or retagging across the terminal full-map finalization boundary.

import ../../../src/state/accumulation_finalization as state_accumulation_finalization
var outcome: AccumulationFinalizationResult[PreparedFinalAccumulation]
outcome.status = AccumulationFinalizationError.None
