# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group":"nominal","expected":"PreparedFinalAccumulation","early":["publishAccumulation(","[3] expected: PreparedFinalAccumulation but got: StateStoreSnapshot"]}

## Detached state snapshots cannot impersonate finalized execution provenance at the dispatcher boundary.

import ../../../src/rpc/server
import ../../../src/state/store
import ../../../src/state/accumulation/completion as accumulation_completion
var owner = default(Server)
var state = default(StateStore)
discard publishAccumulation(owner, state, default(StateStoreSnapshot), default(AccumulationCompositionLimits))
