# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "prefix"}

## A current candidate report prefix cannot be forged or substituted by caller field mutation.
import ../../../src/app/candidate as app_candidate
let prepared = default(PreparedCurrentCandidateReports)
discard prepared.prefix
