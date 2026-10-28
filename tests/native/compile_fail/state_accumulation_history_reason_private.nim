# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Reject raw construction or retagging across authenticated accumulated-history ownership.

import ../../../src/state/accumulation_history as state_accumulation_history
var outcome: AccumulationHistoryResult[PreparedAccumulationHistory]
outcome.status = AccumulationHistoryError.None
