# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## No caller can forge terminal-plan ownership.
import ../../../src/state/accumulation_current_driver as state_accumulation_current_driver
let owner = default(CompletedCurrentAccumulationSequence)
discard owner.data
