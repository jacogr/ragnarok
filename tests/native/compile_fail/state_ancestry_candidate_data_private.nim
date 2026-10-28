# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## External code cannot forge or substitute the original candidate report preparation.
import ../../../src/app/candidate as app_candidate
let owner = PreparedCandidateReports()
discard owner.data
