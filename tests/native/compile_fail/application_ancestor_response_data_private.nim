# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "data"}

## Private request/response fields cannot forge identity, counts, captured headers or result alternatives.
import ../../../src/app/ancestor/response as ancestor_response
let owner = default(AncestorResponse)
discard owner.data
