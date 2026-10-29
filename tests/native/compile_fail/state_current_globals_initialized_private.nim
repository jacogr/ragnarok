# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "initialized"}

## Current global evidence cannot expose or substitute its retained owner graph.
import ../../../src/state/current/globals as current_globals
var value = default(CurrentGlobalSerialization)
discard value.initialized
