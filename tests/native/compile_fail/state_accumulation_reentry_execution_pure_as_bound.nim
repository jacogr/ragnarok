# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "ReentryAccumulationInvocation", "early": ["bootstrapReentry(", "[1] expected: ReentryAccumulationInvocation but got: PreparedAccumulationInvocation"]}

## Reject substitution of nominal reentry bootstrap/completion provenance.

import ../../../src/state/accumulation_reentry_invocation as state_accumulation_reentry_invocation
import ../../../src/state/accumulation_invocation as state_accumulation_invocation
var pure: PreparedAccumulationInvocation
discard bootstrapReentry(pure)
