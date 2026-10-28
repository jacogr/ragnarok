# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged candidate success and unselected stage payloads.
# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/app/candidate as app_candidate
var outcome = default(ApplicationCandidateResult)
discard outcome.status
