# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed wire/default owners cannot expose private successful payload or mutable retained storage.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/state/fuzz_protocol as state_fuzz_protocol
let source = default(FuzzResult[FuzzMessage])
discard source.completed
