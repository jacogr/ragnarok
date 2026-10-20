# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged authentication authority through private storage.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/extrinsic_inputs
var candidate: ExtrinsicInputsResult[int]
discard candidate.status
