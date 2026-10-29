# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default backend operations expose neither reply nor prepared chain prefix.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/app/fuzz/backend as fuzz_backend
import ../../../src/state/fuzz/protocol as fuzz_protocol
let outcome = default(FuzzBackendResult[FuzzMessage])
discard outcome.completed
