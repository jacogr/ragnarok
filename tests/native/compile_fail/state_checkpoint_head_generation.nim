# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bare counter cannot replace the nominal local checkpoint generation.
# @@Verification={"group": "nominal", "expected": "CheckpointGeneration", "early": ["newCheckpointHead(", "[1] expected: CheckpointGeneration but got: uint64"]}
import ../../../src/state/checkpoint/head as checkpoint_head
import ../../../src/codec/state/trie as state_trie
let number = 1'u64
discard newCheckpointHead(number, CheckpointSlot.First, default(StateRoot))
