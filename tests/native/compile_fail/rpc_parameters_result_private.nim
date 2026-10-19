# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: Checks that external mutation of the ParameterResult tag is rejected at compile time.
## Verification: {"group": "privacy", "expected": "success"}

import ../../../src/chain/parameters
var decoded = default(ParameterResult)
decoded.success = true
