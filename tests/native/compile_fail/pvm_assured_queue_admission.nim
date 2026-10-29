# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject private successor queue authority and selected-result storage.

# @@Verification={"group": "privacy", "expected": "admissionReason"}

import ../../../src/state/assured/queue as assured_queue
var candidate: AssuredQueueResult[AssuredAccumulationQueue]
discard candidate.admissionReason
