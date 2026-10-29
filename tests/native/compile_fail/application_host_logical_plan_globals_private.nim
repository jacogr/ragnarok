# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "globals"}

## Host logical authority and backing storage remain private and cannot be retagged or substituted.
import ../../../src/app/collected/supplied/plan as collected_supplied_plan
let source = default(CollectedSuppliedPlan)
discard source.globals
