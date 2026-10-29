# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Outcome storage and result alternatives remain private behind guarded accessors.

import ../../../src/state/accumulation/outcome as accumulation_outcome
var outcome: AccumulationOutcomeResult[AccumulationOutcome]
discard outcome.status
