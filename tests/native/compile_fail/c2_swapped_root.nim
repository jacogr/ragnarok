# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Availability segment roots cannot occupy the erasure commitment role.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: ReportHash but wanted: ReportHash"}

import ../../../src/codec/[c2_records, work_report]
let value = AvailabilitySpec(erasureRoot: SegmentRoot())
discard value
