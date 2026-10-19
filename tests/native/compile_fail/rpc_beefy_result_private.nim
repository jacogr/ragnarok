# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Negative compiler fixture: prevent retagging a failed beefy read as success.
# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/chain/beefy
var decoded = default(BeefyReadResult)
decoded.status = BeefyReadError.None
