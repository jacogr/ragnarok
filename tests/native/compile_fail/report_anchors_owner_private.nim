# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge completed anchor certificates or retag failed results.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/report_anchors
let owner = default(AnchoredReports)
discard owner.data # Must fail before lowering.
