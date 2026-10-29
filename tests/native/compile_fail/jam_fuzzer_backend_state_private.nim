# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## No caller can replace the private seed map after its header identity has been captured.
# @@Verification={"group": "privacy", "expected": "seedState"}
import ../../../src/app/fuzz/backend as fuzz_backend
let backend = default(FuzzBackend)
discard backend.seedState
