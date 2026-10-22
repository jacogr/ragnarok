# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "status"}

## Caller cannot forge complete request association authority or mutate failed alternatives.
import ../../../src/state/preimage_linkage
var value = default(PreimageLinkageResult[CheckedPreimageLinkage])
discard value.status
