# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default preparation results cannot expose a raw fabricated cache owner.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/pvm/step
let prepared = default(PreparationResult[PreparedProgram])
discard prepared.completed
