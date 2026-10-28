# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve nominal root, leaf ordinal and fixed-segment domains.

# @@Verification={"group": "nominal", "expected": "ImportIndex", "early": ["verifyImportSegment(", "[2] expected: ImportIndex but got: FetchItemIndex"]}

import ../../../src/state/import_justification as state_import_justification
import ../../../src/codec/work_package as codec_work_package
import ../../../src/codec/work_report as codec_work_report
import ../../../src/pvm/host_fetch as pvm_host_fetch
discard verifyImportSegment(SegmentRoot(), FetchItemIndex(0), default(FetchSegment), [], default(ImportJustificationLimits))
