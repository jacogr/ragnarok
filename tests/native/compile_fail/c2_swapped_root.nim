# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Availability segment roots cannot occupy the erasure commitment role.
import ../../../src/codec/[c2_records, work_report]
let value = AvailabilitySpec(erasureRoot: SegmentRoot())
discard value
