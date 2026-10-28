# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published trace ownership and successful prefixes remain private behind guarded extraction.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/state/trace_step as state_trace_step
let source = default(TraceStepResult[TraceStep])
discard source.completed
