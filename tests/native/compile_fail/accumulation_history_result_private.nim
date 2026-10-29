# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reject raw construction or retagging across authenticated accumulated-history ownership.

import ../../../src/state/accumulation/history as accumulation_history
var outcome: AccumulationHistoryResult[PreparedAccumulationHistory]
discard outcome.completed
