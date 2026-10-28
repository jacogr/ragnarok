# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject writable credential provenance, result payload or typed failure cause.

# @@Verification={"group": "privacy", "expected": "assignmentReason"}

import ../../../src/state/computed_credentials as state_computed_credentials
var candidate: ComputedCredentialResult[CredentialedComputedReport]
discard candidate.assignmentReason
