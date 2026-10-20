# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject writable credential provenance, result payload or typed failure cause.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/computed_credentials
var candidate: CredentialedComputedReport
discard candidate.data
