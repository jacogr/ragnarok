# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Reject raw construction or retagging across authenticated ready-queue ownership.

import ../../../src/state/accumulation_ready as state_accumulation_ready
var outcome: AccumulationReadyResult[PreparedAccumulationReady]
outcome.status = AccumulationReadyError.None
