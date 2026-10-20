# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject access to private historical lookup ownership and result storage.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/refinement_lookup
var owner: HistoricalLookupResult[HistoricalLookupContext]
discard owner.status
