# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completionReason"}

## Runner discriminators and payloads remain private.

import ../../../src/state/accumulation_runner as state_accumulation_runner
var outcome: AccumulationRunnerResult
discard outcome.completionReason
