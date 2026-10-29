# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject source substitution or a detached numeric budget domain.

# @@Verification={"group": "nominal", "expected": "ByteLimit", "early": ["prepareComputedGuarantee(", "[2] expected: ByteLimit but got: BundleLength"]}

import ../../../src/state/computed/[guarantee as computed_guarantee, report as computed_report]
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
discard prepareComputedGuarantee(default(ComputedWorkReport), BundleLength(1000))
