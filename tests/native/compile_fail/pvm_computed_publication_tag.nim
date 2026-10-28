# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private successor authority or result selection.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/computed_publication as state_computed_publication
var candidate: ComputedPublicationResult[ComputedReportSuccessor]
discard candidate.status
