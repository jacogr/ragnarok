# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/failed Genesis or bootstrap alternatives cannot expose trusted successful prefixes through public fields.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/state/trace_genesis as state_trace_genesis
let source = default(TraceGenesis)
discard source.data
