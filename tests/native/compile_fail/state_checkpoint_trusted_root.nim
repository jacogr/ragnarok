# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A trie node identity cannot stand in for independently trusted complete-state authority.
# @@Verification={"group": "nominal", "expected": "StateRoot", "early": ["decodeFullCheckpoint(", "[2] expected: StateRoot but got: StateNodeHash"]}
import ../../../src/state/[checkpoint, store]
import ../../../src/codec/[state_layout, bounded]
let bytes: seq[byte] = @[]
discard decodeFullCheckpoint(bytes, default(StateNodeHash), default(StateStoreLimits), ByteLimit(100))
