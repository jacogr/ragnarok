# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Complete activity ownership and result alternatives remain private.

import ../../../src/state/accumulation_activity as state_accumulation_activity
var outcome: AccumulationActivityResult[int]
outcome.status = AccumulationActivityError.None
