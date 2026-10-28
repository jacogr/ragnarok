# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "PreparedCurrentChainUpdate", "early": ["captureCurrentUpdateCheckpoint(", "[1] expected: PreparedCurrentChainUpdate but got: StateStoreSnapshot"]}

## A detached complete map cannot manufacture authenticated execution provenance.
import ../../../src/state/current_checkpoint as state_current_checkpoint
import ../../../src/state/store as state_store
import ../../../src/codec/bounded as codec_bounded
discard captureCurrentUpdateCheckpoint(default(StateStoreSnapshot), ByteLimit(524288))
