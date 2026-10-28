# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "ReadySnapshot", "early": ["projectAccumulationReady(", "[1] expected: ReadySnapshot but got: StateStoreSnapshot"]}

## Refuse substituting a projection for bound history or a full map for a ready ring.

import ../../../src/state/accumulation_ready as state_accumulation_ready
import ../../../src/state/store as state_store
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/header as codec_header
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/header as codec_header
var state: StateStoreSnapshot
var config: AccumulationReadyConfig
discard projectAccumulationReady(state, default(AccumulatedSnapshot), [], [], HeaderSlot(0),
    HeaderSlot(1), config)
