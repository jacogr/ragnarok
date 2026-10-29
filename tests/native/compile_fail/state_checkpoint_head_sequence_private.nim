# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local head fields remain immutable behind initialized read accessors.
# @@Verification={"group": "privacy", "expected": "sequence"}
import ../../../src/state/checkpoint/head as checkpoint_head
let head = default(CheckpointHead)
discard head.sequence
