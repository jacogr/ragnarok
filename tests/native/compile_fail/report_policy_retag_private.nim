# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Policy certificates and result internals remain private across application boundaries.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/report_policy
let owner = default(ReportPolicyResult[PolicyCheckedReports])
discard owner.status # Must fail before lowering.
