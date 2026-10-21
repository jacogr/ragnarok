# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot retag codec results or replace private success payloads.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/app/checkpoint_identity
let outcome = default(ApplicationCheckpointIdentityResult)
discard outcome.completed
