# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Opaque immutable prices and selected-result payloads cannot be forged or inspected through raw fields.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/pvm/gas/plan as gas_plan
let held = default(GasPlanResult[GasPlan])
discard held.completed
