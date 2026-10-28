# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Only actual worker completion selects the performed operation; callers cannot rewrite its private alternative.
# @@Verification={"group": "privacy", "expected": "performed"}
import ../../../src/app/checkpoint_worker as app_checkpoint_worker
let completed = default(ApplicationCheckpointCompletion)
discard completed.performed
