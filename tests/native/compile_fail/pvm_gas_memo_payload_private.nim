# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque source/policy-bound lazy prices and selected-result payloads cannot be forged or inspected through raw fields.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/pvm/gas_memo as pvm_gas_memo
let held = default(GasMemoResult[GasMemo])
discard held.completed
