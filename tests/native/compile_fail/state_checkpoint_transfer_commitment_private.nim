# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Prepared payload and discriminator cannot escape the sole owner.
# @@Verification={"group": "privacy", "expected": "commitment"}
import ../../../src/state/checkpoint/transfer as checkpoint_transfer
let checkpoint = default(PreparedCheckpoint)
discard checkpoint.commitment
