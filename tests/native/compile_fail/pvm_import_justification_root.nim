# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject package hashes as segment roots; this compiler prints both generic domains as ReportHash.

# @@Verification={"group": "nominal", "expected": "ReportHash", "early": ["verifyImportSegment(", "[1] expected: ReportHash but got: ReportHash"]}

import ../../../src/state/import_justification
import ../../../src/codec/[work_package, work_report]
import ../../../src/pvm/host_fetch
discard verifyImportSegment(PackageHash(), ImportIndex(0), default(FetchSegment), [], default(ImportJustificationLimits))
