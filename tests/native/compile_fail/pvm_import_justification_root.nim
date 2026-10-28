# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject package hashes as segment roots; this compiler prints both generic domains as ReportHash.

# @@Verification={"group": "nominal","expected": "ReportHash","early": ["verifyImportSegment(","[1] expected: ReportHash[2] but got: ReportHash[0]"]}

import ../../../src/state/import_justification as state_import_justification
import ../../../src/codec/work_package as codec_work_package
import ../../../src/codec/work_report as codec_work_report
import ../../../src/pvm/host_fetch as pvm_host_fetch
discard verifyImportSegment(PackageHash(), ImportIndex(0), default(FetchSegment), [], default(ImportJustificationLimits))
