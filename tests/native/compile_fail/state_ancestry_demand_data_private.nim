# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## External code cannot forge the retained ancestry, discovery or prepared admission certificate.
import ../../../src/state/report_anchors
let owner = default(ReportLookupDemand)
discard owner.data
