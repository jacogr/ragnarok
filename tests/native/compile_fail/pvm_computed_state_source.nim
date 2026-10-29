# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached transcript or map as completed provenance.

# @@Verification={"group": "nominal", "expected": "ComputedReportLinks", "early": ["bindComputedState(", "[1] expected: ComputedReportLinks but got: ComputedGuaranteeTranscript"]}

import ../../../src/state/computed/[state as computed_state, links as computed_links,
    guarantee as computed_guarantee]
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/store
discard bindComputedState(default(ComputedGuaranteeTranscript), default(BlockAdmissionResult))
