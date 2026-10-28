# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "info"}

## Caller cannot forge or mutate private source-bound audit authority.
import ../../../src/state/footprint_audit as state_footprint_audit
var value = default(CheckedAccountFootprints)
discard value.info
