# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed observation/options owners cannot expose private successful state.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/app/trace_import
let source = default(TraceImportResult)
discard source.completed
