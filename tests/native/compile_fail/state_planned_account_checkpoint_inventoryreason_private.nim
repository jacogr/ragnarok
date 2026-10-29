# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "inventoryReason"}

## Caller cannot forge expected-root account evidence or rewrite failed phase alternatives.
import ../../../src/state/planned/account_checkpoint as planned_account_checkpoint
var value = default(PlannedAccountCheckpointResult)
discard value.inventoryReason
