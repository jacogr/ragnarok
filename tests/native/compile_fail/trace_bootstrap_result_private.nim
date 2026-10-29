# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/failed Genesis or bootstrap alternatives cannot expose trusted successful prefixes through public fields.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/app/trace/bootstrap as trace_bootstrap
let source = default(TraceBootstrapResult)
discard source.completed
