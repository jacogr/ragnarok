# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Refuse raw construction or retagging of original-block-bound ready reconciliation.

import ../../../src/state/ready_reconciliation
var outcome: ReadyReconciliationResult[PreparedReadyReconciliation]
outcome.status = ReadyReconciliationError.None
