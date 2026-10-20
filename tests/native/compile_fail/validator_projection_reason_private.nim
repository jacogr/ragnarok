# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Projection owners and result alternatives remain private.

import ../../../src/state/validator_projection
var outcome: ValidatorActivityResult[int]
outcome.status = ValidatorActivityError.None
