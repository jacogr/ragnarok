# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Policy certificates and result internals remain private across application boundaries.
import ../../../src/state/report_policy
let owner = default(PolicyCheckedReports)
discard owner.data # Must fail before lowering.
