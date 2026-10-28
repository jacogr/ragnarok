# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: callers cannot retag a failed finality selection into success.
# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/chain/provider as chain_provider
var result = default(ViewFinalizeResult)
result.status = ViewFinalizeError.None
