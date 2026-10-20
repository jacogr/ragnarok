# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private successor authority or result selection.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_publication
var candidate: ComputedReportSuccessor
discard candidate.data
