# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private bootstrap or historical-preimage alternative storage.

# @@Verification={"group": "privacy", "expected": "stored"}

import ../../../src/state/refinement_lookup as state_refinement_lookup
var owner: HistoricalPreimage
discard owner.stored
