# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <PreparationWorker>", "build_name": "application-preparation-worker-copy"}

## Reject duplicated composite thread owners during actual ownership lowering.
import ../../../src/app/preparation_worker
var original = default(PreparationWorker)
var duplicate = original
original.close()
duplicate.close()
