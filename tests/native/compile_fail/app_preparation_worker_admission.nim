# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "ticket"}

## Private worker authority cannot be forged or retagged by callers.
import ../../../src/app/preparation_worker as app_preparation_worker
let private = default(PreparationAdmission)
discard private.ticket
