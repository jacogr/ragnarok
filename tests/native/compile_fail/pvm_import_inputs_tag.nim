# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged import-manifest authority through private storage.

# @@Verification={"group": "privacy", "expected": "status"}

import "../../../src/state/import/inputs" as import_inputs
var candidate: ImportInputsResult[int]
discard candidate.status
