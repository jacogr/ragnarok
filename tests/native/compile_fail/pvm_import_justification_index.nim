# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve nominal root, leaf ordinal and fixed-segment domains.

# @@Verification={"group": "nominal", "expected": "ImportIndex", "early": ["verifyImportSegment(", "[2] expected: ImportIndex but got: FetchItemIndex"]}

import "../../../src/state/import/justification" as import_justification
import ../../../src/codec/work/[package as work_package, report as work_report]
import ../../../src/pvm/host/fetch as host_fetch
discard verifyImportSegment(SegmentRoot(), FetchItemIndex(0), default(FetchSegment), [], default(ImportJustificationLimits))
