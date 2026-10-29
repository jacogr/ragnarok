# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject source substitution or a detached numeric budget domain.

# @@Verification={"group": "nominal", "expected": "ComputedWorkReport", "early": ["prepareComputedGuarantee(", "[1] expected: ComputedWorkReport but got: AvailabilityCommitment"]}

import ../../../src/state/computed/guarantee as computed_guarantee
import ../../../src/state/availability/specifier as availability_specifier
import ../../../src/codec/bounded
import ../../../src/codec/work/report as work_report
discard prepareComputedGuarantee(default(AvailabilityCommitment), ByteLimit(1000))
