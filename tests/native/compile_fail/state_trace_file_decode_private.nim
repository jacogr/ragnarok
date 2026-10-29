# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## File/default/refused trace alternatives cannot expose a successful owner or decode prefix through public fields.
# @@Verification={"group": "privacy", "expected": "decodeReason"}
import ../../../src/state/trace/file as trace_file
let source = default(TraceFileResult)
discard source.decodeReason
