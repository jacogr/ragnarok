# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Complete activity ownership and result alternatives remain private.

import ../../../src/state/accumulation_activity
var owner: PreparedAccumulationActivity
discard owner.data
