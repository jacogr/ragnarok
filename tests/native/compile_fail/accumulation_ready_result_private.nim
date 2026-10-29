# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reject raw construction or retagging across authenticated ready-queue ownership.

import ../../../src/state/accumulation/ready as accumulation_ready
var outcome: AccumulationReadyResult[PreparedAccumulationReady]
discard outcome.completed
