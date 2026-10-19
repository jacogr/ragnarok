# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse raw construction or retagging across the finalized statistics boundary.

import ../../../src/state/accumulation_statistics
var plan: PreparedAccumulationStatistics
discard plan.data
