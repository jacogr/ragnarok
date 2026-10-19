# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Reject private reentry preparation storage access.

import ../../../src/state/accumulation_reentry
var owner: PreparedAccumulationReentry
discard owner.data
