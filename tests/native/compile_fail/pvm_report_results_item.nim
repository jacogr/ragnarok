# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject public result forgery, source rebinding and mixed report retention domains.

# @@Verification={"group": "privacy", "expected": "data"}

import ../../../src/state/refinement_report
var owner: RefinedWorkItem
discard owner.data
