# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached identities/availability tuples and substituted memory-policy domains.

# @@Verification={"group": "nominal", "expected": "ByteLimit", "early": ["prepareComputedReport(", "[2] expected: ByteLimit but got: BundleLength"]}

import ../../../src/state/computed/report as computed_report
import ../../../src/state/report/identity as report_identity
import ../../../src/state/availability/specifier as availability_specifier
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
discard prepareComputedReport(default(AvailabilityCommitment), BundleLength(1000))
