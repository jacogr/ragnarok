# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "consensusReason"}

## Completion tags, successful candidates and phase-reason storage remain private.

import ../../../src/state/accumulation/completion as accumulation_completion
var outcome: AccumulationCompletionResult
discard outcome.consensusReason
