# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Reject raw construction or retagging across authenticated ready-queue ownership.

import ../../../src/state/accumulation_ready
var plan: PreparedAccumulationReady
discard plan.data
