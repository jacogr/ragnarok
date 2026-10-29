# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Composite native thread/bank/buffer ownership independently rejects actual ARC duplication.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <CheckpointWorker>", "build_name": "state-checkpoint-worker-copy"}
import ../../../src/state/checkpoint/worker as checkpoint_worker
var original = default(CheckpointWorker)
var duplicate = original
discard original.close()
discard duplicate.close()
