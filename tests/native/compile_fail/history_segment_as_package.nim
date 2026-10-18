# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Segment commitments cannot silently become dictionary package identities.
import ../../../src/codec/state_history
var root: SegmentRoot
let pair = ReportedPackage(package: root)
discard pair
