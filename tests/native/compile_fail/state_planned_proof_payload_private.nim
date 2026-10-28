# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "completed"}

## Planned authentication results cannot expose or forge their success alternative.
import ../../../src/state/planned_proof as state_planned_proof
let private = default(PlannedProofResult[bool])
discard private.completed
