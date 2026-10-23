# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Managed proof tickets and tagged failure storage cannot be forged or retagged externally.
import ../../../src/app/services
let source = default(LogicalProofAdmission)
discard source.status
