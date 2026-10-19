# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: prevent retagging a failed statistics read as success.
## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/chain/statistics
var decoded = default(StatisticsReadResult)
decoded.status = StatisticsReadError.None
