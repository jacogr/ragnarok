# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reject private reentry preparation storage access.

import ../../../src/state/accumulation_reentry
var result: AccumulationReentryResult[int]
discard result.completed
