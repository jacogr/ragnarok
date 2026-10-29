# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "PreparedCurrentChainUpdate", "early": ["captureCurrentUpdateCheckpoint(", "[1] expected: PreparedCurrentChainUpdate but got: StateStoreSnapshot"]}

## A detached complete map cannot manufacture authenticated execution provenance.
import ../../../src/state/current/checkpoint as current_checkpoint
import ../../../src/state/store
import ../../../src/codec/bounded
discard captureCurrentUpdateCheckpoint(default(StateStoreSnapshot), ByteLimit(524288))
