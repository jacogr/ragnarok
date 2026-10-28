# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Reject private reentry bootstrap/completion payload access.

import ../../../src/state/accumulation_reentry_invocation as state_accumulation_reentry_invocation
var result: AccumulationReentryInvocationResult[int]
discard result.completed
