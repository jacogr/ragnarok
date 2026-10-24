# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque RawState ownership cannot be replaced by caller-authored wire or map storage.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/state/trace_state
let state = default(TraceState)
discard state.data
