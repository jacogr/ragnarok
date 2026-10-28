# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private captured facts cannot be retagged or replaced by callers.
# @@Verification={"group": "privacy", "expected": "timeslot"}
import ../../../src/app/checkpoint_identity as app_checkpoint_identity
let identity = default(ApplicationCheckpointIdentity)
discard identity.timeslot
