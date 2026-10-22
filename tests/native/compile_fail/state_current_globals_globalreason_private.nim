# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "globalReason"}

## Current global evidence cannot expose or substitute its retained owner graph.
import ../../../src/state/current_globals
var value = default(CurrentGlobalsResult[CurrentGlobalSerialization])
discard value.globalReason
