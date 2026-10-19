# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "ContinuationAccumulationInvocation", "early": ["bootstrapContinuation(", "[1] expected: ContinuationAccumulationInvocation but got: PreparedAccumulationInvocation"]}

## Reject replacement of nominal continuation invocation provenance.

import ../../../src/state/[accumulation_continuation_invocation, accumulation_invocation]
var pure: PreparedAccumulationInvocation
discard bootstrapContinuation(pure)
