# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged private bundle-erasure authority.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/bundle_erasure as state_bundle_erasure
var candidate: BundleErasureResult[BundleErasure]
discard candidate.completed
