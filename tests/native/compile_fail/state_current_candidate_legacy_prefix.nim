# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentCandidateReports but got: PreparedCandidateReports", "early": ["completeCurrentCandidateReports(", "[2] expected: PreparedCurrentCandidateReports but got: PreparedCandidateReports"]}

## Current frozen completion policy is not supplied by a legacy-only report owner.
import ../../../src/app/candidate as app_candidate
import ../../../src/app/chain as app_chain
discard completeCurrentCandidateReports(default(ApplicationChain), default(
    PreparedCandidateReports), [])
