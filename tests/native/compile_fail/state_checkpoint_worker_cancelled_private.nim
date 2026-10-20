# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot reclassify real publication through a mutable cancellation flag.
# @@Verification={"group": "privacy", "expected": "cancelled"}
import ../../../src/state/checkpoint_worker
let worker = default(CheckpointWorker)
discard worker.cancelled
