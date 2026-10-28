# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private result storage cannot bypass success contracts.
# @@Verification={"group": "privacy", "expected": "status"}
import ../../../src/state/checkpoint_head as state_checkpoint_head
let outcome = default(CheckpointHeadResult[CheckpointHead])
discard outcome.status
