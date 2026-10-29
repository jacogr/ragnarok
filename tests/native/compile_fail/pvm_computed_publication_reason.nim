# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private successor authority or result selection.

# @@Verification={"group": "privacy", "expected": "storeReason"}

import ../../../src/state/computed/publication as computed_publication
var candidate: ComputedPublicationResult[ComputedReportSuccessor]
discard candidate.storeReason
