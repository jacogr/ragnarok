# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Complete activity ownership and result alternatives remain private.

import ../../../src/state/accumulation_activity
var outcome: AccumulationActivityResult[int]
discard outcome.completed
