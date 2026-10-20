# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject a detached transcript or map as completed provenance.

# @@Verification={"group": "nominal", "expected": "ComputedReportLinks", "early": ["bindComputedState(", "[1] expected: ComputedReportLinks but got: ComputedGuaranteeTranscript"]}

import ../../../src/state/[computed_state, computed_links, computed_guarantee, block_admission, store]
discard bindComputedState(default(ComputedGuaranteeTranscript), default(BlockAdmissionResult))
