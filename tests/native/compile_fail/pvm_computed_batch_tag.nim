# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private batch authority or result selection.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/computed_batch
var outcome: ComputedBatchResult[int]
discard outcome.status
