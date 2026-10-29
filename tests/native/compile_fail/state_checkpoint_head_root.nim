# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Internal node hashes cannot become complete checkpoint roots.
# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["newCheckpointHead(", "[3] expected: StateRoot but got: StateNodeHash"]}
import ../../../src/state/checkpoint/head as checkpoint_head
import ../../../src/codec/state/layout as state_layout
discard newCheckpointHead(CheckpointGeneration(0), CheckpointSlot.First, default(StateNodeHash))
