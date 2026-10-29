# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "refused"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/current/logical as current_logical
let source = default(CollectedLogicalPlanResult)
discard source.refused
