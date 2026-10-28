# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A trie node identity cannot stand in for independently trusted complete-state authority.
# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["decodeFullCheckpoint(", "[2] expected: StateRoot but got: StateNodeHash"]}
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded
let bytes: seq[byte] = @[]
discard decodeFullCheckpoint(bytes, default(StateNodeHash), default(StateStoreLimits), ByteLimit(100))
