# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Refused unions cannot expose a private completed payload.

import ../../../src/state/accumulation_provisions
var outcome: AccumulationProvisionResult[int]
discard outcome.completed
