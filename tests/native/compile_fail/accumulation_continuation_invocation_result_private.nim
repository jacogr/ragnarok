# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Reject private continuation invocation storage access.

import ../../../src/state/accumulation_continuation_invocation
var result: AccumulationContinuationInvocationResult[int]
result.status = AccumulationContinuationInvocationError.None
