# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native threads and cooperative writer locks retain one stable composite owner during actual lowering.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <ApplicationCheckpointWorker>", "build_name": "application-checkpoint-worker-copy"}
import ../../../src/app/checkpoint/worker as checkpoint_worker
var original = default(ApplicationCheckpointWorker)
var duplicate = original
discard original.close()
discard duplicate.close()
