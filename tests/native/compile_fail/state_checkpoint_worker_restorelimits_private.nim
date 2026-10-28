# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller trust and resource ceilings cannot be replaced outside synchronized admission.
# @@Verification={"group": "privacy", "expected": "restoreLimits"}
import ../../../src/state/checkpoint_worker as state_checkpoint_worker
let worker = default(CheckpointWorker)
discard worker.restoreLimits
