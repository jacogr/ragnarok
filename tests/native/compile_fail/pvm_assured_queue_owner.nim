# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private successor queue authority and selected-result storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/assured_queue
var candidate: AssuredAccumulationQueue
discard candidate.data
