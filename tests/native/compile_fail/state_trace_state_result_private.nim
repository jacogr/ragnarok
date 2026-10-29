# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default RawState alternatives cannot expose a successful owner prefix.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/state/trace/state as trace_state
let outcome = default(TraceStateResult[TraceState])
discard outcome.completed
