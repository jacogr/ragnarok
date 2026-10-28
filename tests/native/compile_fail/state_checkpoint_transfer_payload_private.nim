# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared payload and discriminator cannot escape the sole owner.
# @@Verification={"group": "privacy", "expected": "payload"}
import ../../../src/state/checkpoint_transfer as state_checkpoint_transfer
let checkpoint = default(PreparedCheckpoint)
discard checkpoint.payload
