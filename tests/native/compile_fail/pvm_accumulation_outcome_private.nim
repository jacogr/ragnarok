# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Outcome storage and result alternatives remain private behind guarded accessors.

import ../../../src/state/accumulation_outcome
var owner: AccumulationOutcome
discard owner.data
