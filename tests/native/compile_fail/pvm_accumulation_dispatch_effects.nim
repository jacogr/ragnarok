# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completedEffects"}

## Dispatch effects remain private behind the selected-success accessor.

import ../../../src/state/accumulation_dispatch
var outcome: AccumulationDispatchResult
discard outcome.completedEffects
