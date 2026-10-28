# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached identities/availability tuples and substituted memory-policy domains.

# @@Verification={"group": "nominal", "expected": "AvailabilityCommitment", "early": ["prepareComputedReport(", "[1] expected: AvailabilityCommitment but got: ReportIdentity"]}

import ../../../src/state/computed_report as state_computed_report
import ../../../src/state/report_identity as state_report_identity
import ../../../src/state/availability_specifier as state_availability_specifier
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/work_report as codec_work_report
discard prepareComputedReport(default(ReportIdentity), ByteLimit(1000))
