# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "invocationReason"}

## Reject private continuation invocation storage access.

import ../../../src/state/accumulation/continuation/invocation as accumulation_continuation_invocation
var result: AccumulationContinuationInvocationResult[int]
discard result.invocationReason
