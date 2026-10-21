# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Worker resources and ticket authority remain private.
# @@Verification={"group": "privacy", "expected": "ticket"}
import ../../../src/app/checkpoint_worker
let owner = default(ApplicationCheckpointAdmission)
discard owner.ticket
