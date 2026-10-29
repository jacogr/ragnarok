# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private worker state and receipt alternatives cannot bypass lifecycle or success guards.
# @@Verification={"group": "privacy", "expected": "owner"}
import ../../../src/state/checkpoint/worker as checkpoint_worker
let owner = default(CheckpointTicket)
discard owner.owner
