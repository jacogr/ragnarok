# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A failed/default offline command cannot be retagged or expose a successful final root.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/app/trace_check_command
let source = default(TraceCheckCommandOutcome)
discard source.status
