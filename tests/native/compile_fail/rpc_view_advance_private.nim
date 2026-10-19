# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: callers cannot retag a failed history advance into success.
# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/chain/provider
var result = default(ViewAdvanceResult)
result.status = ViewAdvanceError.None
