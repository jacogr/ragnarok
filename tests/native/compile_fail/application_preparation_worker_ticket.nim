# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "owner"}

## Private worker authority cannot be forged or retagged by callers.
import ../../../src/app/preparation_worker
let private = default(PreparationTicket)
discard private.owner
