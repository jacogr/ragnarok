# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Default preparation results cannot expose private selected payloads.
import ../../../src/state/accumulation_current_update
let outcome = default(CurrentChainPreparationResult)
discard outcome.status
