# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge the decoder-owned arithmetic destination through a copied coordinate object.
# @@Verification={"group": "privacy", "expected": "writeSlot"}
import ../../../src/pvm/program as pvm_program
let slots = default(RegisterSlots)
discard slots.writeSlot
