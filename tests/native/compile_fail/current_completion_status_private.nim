# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Callers cannot select completion success or failed-child alternatives.
import ../../../src/state/accumulation/current/completion as accumulation_current_completion
let outcome = default(CurrentAccumulationCompletionResult)
discard outcome.status
