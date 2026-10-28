# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject using a work-item ordinal as an extrinsic-input ordinal.

# @@Verification={"group": "nominal", "expected": "ExtrinsicInputIndex", "early": ["extrinsicInput(", "[3] expected: ExtrinsicInputIndex but got: FetchItemIndex"]}

import ../../../src/state/extrinsic_inputs as state_extrinsic_inputs
import ../../../src/pvm/host_fetch as pvm_host_fetch
discard extrinsicInput(default(VerifiedExtrinsics), FetchItemIndex(0), FetchItemIndex(0))
