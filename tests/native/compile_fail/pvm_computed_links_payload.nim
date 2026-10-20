# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged lookup-owner storage or selected result alternatives.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/computed_links
var candidate: ComputedLinksResult[ComputedReportLinks]
discard candidate.completed
