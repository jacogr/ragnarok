# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot retag a live thread's selected borrowed graph.
# @@Verification={"group": "privacy", "expected": "operation"}

import ../../../src/app/preparation_worker as app_preparation_worker
var worker = default(PreparationWorker)
discard worker.operation
