# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged lookup-owner storage or selected result alternatives.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_links
var candidate: ComputedReportLinks
discard candidate.data
