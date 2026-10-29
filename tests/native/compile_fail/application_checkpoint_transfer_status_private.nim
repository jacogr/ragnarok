# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Sole bytes, initialized context and typed refusal tags cannot be rewritten by consumers.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/app/checkpoint/transfer as checkpoint_transfer
let prepared = default(PreparedApplicationCheckpoint)
discard prepared.status
