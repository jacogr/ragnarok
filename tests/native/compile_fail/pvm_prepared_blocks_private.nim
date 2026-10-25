# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared program ownership and its selected operation arrays are never writable public state.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/pvm/step
let prepared = default(PreparedProgram)
discard prepared.data
