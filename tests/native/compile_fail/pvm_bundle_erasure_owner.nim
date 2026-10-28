# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject forged private bundle-erasure authority.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/bundle_erasure as state_bundle_erasure
var candidate: BundleErasure
discard candidate.data
