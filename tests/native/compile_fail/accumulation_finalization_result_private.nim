# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reject raw construction or retagging across the terminal full-map finalization boundary.

import ../../../src/state/accumulation/finalization as accumulation_finalization
var outcome: AccumulationFinalizationResult[PreparedFinalAccumulation]
discard outcome.completed
