# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Certified validator ownership and result alternatives remain private.

import ../../../src/state/accumulation_validators
var outcome: AccumulationValidatorsResult[int]
outcome.status = AccumulationValidatorsError.None
