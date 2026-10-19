# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Segment commitments cannot silently become dictionary package identities.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: ReportHash but wanted: ReportHash"}

import ../../../src/codec/state_history
var root: SegmentRoot
let pair = ReportedPackage(package: root)
discard pair
