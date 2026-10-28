# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trace map or execution failure cannot expose a usable prepared prefix through public fields.
# @@Verification={"group": "privacy", "expected": "candidateReason"}
import ../../../src/app/trace_import as app_trace_import
let source = default(TraceImportResult)
discard source.candidateReason
