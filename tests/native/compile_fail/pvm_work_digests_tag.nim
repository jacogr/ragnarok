# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject digest result forgery, writable retained storage and detached source substitution.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/refinement_digest
var value: RefinementDigestResult[RefinementDigests]
discard value.status
