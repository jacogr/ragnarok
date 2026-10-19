# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedAccumulationContinuation", "early": ["prepareAccumulationReentry(", "[1] expected: CompletedAccumulationContinuation but got: CompletedAccumulationReentry"]}

## Reject substitution of nominal reentry bootstrap/completion provenance.

import ../../../src/state/[accumulation_reentry, accumulation_reentry_execution]
var completed: CompletedAccumulationReentry
discard prepareAccumulationReentry(completed, default(AccumulationReentryConfig))
