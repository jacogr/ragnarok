# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject source substitution or a detached numeric budget domain.

# @@Verification={"group": "nominal", "expected": "ComputedWorkReport", "early": ["prepareComputedGuarantee(", "[1] expected: ComputedWorkReport but got: AvailabilityCommitment"]}

import ../../../src/state/[computed_guarantee, availability_specifier]
import ../../../src/codec/[bounded, work_report]
discard prepareComputedGuarantee(default(AvailabilityCommitment), ByteLimit(1000))
