# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "serviceReason"}

## Reject private reentry bootstrap/completion payload access.

import ../../../src/state/accumulation/reentry/invocation as accumulation_reentry_invocation
var result: AccumulationReentryInvocationResult[int]
discard result.serviceReason
