# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached identities/availability tuples and substituted memory-policy domains.

# @@Verification={"group": "nominal", "expected": "AvailabilityCommitment", "early": ["prepareComputedReport(", "[1] expected: AvailabilityCommitment but got: ReportIdentity"]}

import ../../../src/state/[computed_report, report_identity, availability_specifier]
import ../../../src/codec/[bounded, work_report]
discard prepareComputedReport(default(ReportIdentity), ByteLimit(1000))
