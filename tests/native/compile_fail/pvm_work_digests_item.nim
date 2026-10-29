# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject digest result forgery, writable retained storage and detached source substitution.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/refinement/digest as refinement_digest
var owner: RefinedDigest
discard owner.data
