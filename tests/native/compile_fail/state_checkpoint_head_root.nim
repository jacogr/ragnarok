# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Internal node hashes cannot become complete checkpoint roots.
# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["newCheckpointHead(", "[3] expected: StateRoot but got: StateNodeHash"]}
import ../../../src/state/checkpoint_head as state_checkpoint_head
import ../../../src/codec/state_layout as codec_state_layout
discard newCheckpointHead(CheckpointGeneration(0), CheckpointSlot.First, default(StateNodeHash))
