# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Certified validator ownership and result alternatives remain private.

import ../../../src/state/accumulation_validators as state_accumulation_validators
var outcome: AccumulationValidatorsResult[int]
discard outcome.completed
