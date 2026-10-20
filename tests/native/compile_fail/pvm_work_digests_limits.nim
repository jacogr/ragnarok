# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject digest result forgery, writable retained storage and detached source substitution.

# @@Verification={"group": "nominal", "expected": "got: ElementLimit but wanted: ByteLimit"}

import ../../../src/state/refinement_digest
import ../../../src/codec/bounded
discard RefinementDigestLimits(encoding: ElementLimit(1))
