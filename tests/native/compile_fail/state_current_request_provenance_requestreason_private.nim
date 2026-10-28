# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "requestReason"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
let source = default(CurrentChainPreparationResult)
discard source.requestReason
