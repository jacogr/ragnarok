# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject composition result forgery, source replacement and mixed independent retention domains.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/authorized_refinement
var owner: AuthorizedRefinement
discard owner.data
