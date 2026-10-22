# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "reason"}

## Reject mutable or partial-state shortcuts at the complete-manifest boundary.
import ../../../src/state/manifest
let private = default(StateManifestResult[bool])
discard private.reason
