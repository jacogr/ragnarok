# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge report-stage identity, success or its retained profile.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/report_admission as state_report_admission
let value = default(AdmittedReports)
discard value.data # Private storage must be rejected before lowering.
