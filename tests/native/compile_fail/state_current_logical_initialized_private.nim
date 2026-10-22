# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "initialized"}

## Logical current provenance and tagged payloads remain private.
import ../../../src/state/current_logical
var owner = default(CurrentLogicalState)
discard owner.initialized
