# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Refuse access or domain substitution across continuation input/state preparation.

import ../../../src/state/accumulation_continuation_inputs
var plan: PreparedAccumulationContinuationInputs
discard plan.data
