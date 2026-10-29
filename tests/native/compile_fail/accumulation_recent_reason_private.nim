# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Reject mutable construction or payload extraction across private recent-history ownership.

import ../../../src/state/accumulation/recent as accumulation_recent
var outcome: AccumulationRecentResult[PreparedAccumulationRecent]
outcome.status = AccumulationRecentError.None
