# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque source/policy-bound lazy prices and selected-result payloads cannot be forged or inspected through raw fields.
# @@Verification={"group": "privacy", "expected": "data"}
import ../../../src/pvm/gas/memo as gas_memo
let held = default(GasMemo)
discard held.data
