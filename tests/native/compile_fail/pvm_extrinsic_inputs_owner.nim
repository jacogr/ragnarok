# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged authentication authority through private storage.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/extrinsic_inputs as state_extrinsic_inputs
var candidate: VerifiedExtrinsics
discard candidate.data
