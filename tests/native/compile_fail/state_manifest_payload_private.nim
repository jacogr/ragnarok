# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Reject mutable or partial-state shortcuts at the complete-manifest boundary.
import ../../../src/state/manifest as state_manifest
let private = default(StateManifestResult[bool])
discard private.completed
