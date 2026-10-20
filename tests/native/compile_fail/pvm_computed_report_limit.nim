# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject detached identities/availability tuples and substituted memory-policy domains.

# @@Verification={"group": "nominal", "expected": "ByteLimit", "early": ["prepareComputedReport(", "[2] expected: ByteLimit but got: BundleLength"]}

import ../../../src/state/[computed_report, report_identity, availability_specifier]
import ../../../src/codec/[bounded, work_report]
discard prepareComputedReport(default(AvailabilityCommitment), BundleLength(1000))
