# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "completed"}

## Source-bound authorization owners, result payloads and tags remain private.

import ../../../src/state/accumulation_authorization
var owner: AccumulationAuthorizationResult[int]
discard owner.completed
