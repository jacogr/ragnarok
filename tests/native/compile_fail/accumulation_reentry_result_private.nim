# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Reject private reentry preparation storage access.

import ../../../src/state/accumulation/reentry as accumulation_reentry
var result: AccumulationReentryResult[int]
result.status = AccumulationReentryError.None
