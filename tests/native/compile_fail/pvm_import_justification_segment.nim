# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve nominal root, leaf ordinal and fixed-segment domains.

# @@Verification={"group": "nominal", "expected": "FetchSegment", "early": ["verifyImportSegment(", "[3] expected: FetchSegment but got: seq"]}

import "../../../src/state/import/justification" as import_justification
import ../../../src/codec/work/[package as work_package, report as work_report]
import ../../../src/pvm/host_fetch
discard verifyImportSegment(SegmentRoot(), ImportIndex(0), newSeq[byte](4104), [], default(ImportJustificationLimits))
