# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse access or substitution across the admitted execution certificate boundary.

import ../../../src/state/accumulation_execution as state_accumulation_execution
var plan: CompletedBlockAccumulation
discard plan.data
