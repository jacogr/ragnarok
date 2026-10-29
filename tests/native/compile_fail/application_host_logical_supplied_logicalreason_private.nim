# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "logicalReason"}

## Host logical authority and backing storage remain private and cannot be retagged or substituted.
import ../../../src/app/collected/supplied/state as collected_supplied_state
let source = default(CollectedSuppliedResult)
discard source.logicalReason
