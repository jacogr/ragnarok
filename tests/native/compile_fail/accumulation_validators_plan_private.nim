# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Certified validator ownership and result alternatives remain private.

import ../../../src/state/accumulation/validators as accumulation_validators
var owner: PreparedAccumulationValidators
discard owner.data
