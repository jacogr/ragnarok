# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Reject private continuation completion payload access.

import ../../../src/state/accumulation/continuation/execution as accumulation_continuation_execution
var owner: CompletedAccumulationContinuation
discard owner.data
