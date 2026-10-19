# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Callers cannot retag a refused union as successful.

import ../../../src/state/accumulation_provisions
var outcome: AccumulationProvisionResult[int]
outcome.status = AccumulationProvisionError.None
