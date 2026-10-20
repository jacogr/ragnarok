# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Reject mutable construction or payload extraction across private recent-history ownership.

import ../../../src/state/accumulation_recent
var owner: PreparedAccumulationRecent
discard owner.data
