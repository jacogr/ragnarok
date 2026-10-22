# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## No caller can forge or replace retained source history, report range or transfer classification.
import ../../../src/state/accumulation_current_sequence
let owner = default(PreparedCurrentContinuation)
discard owner.data
