# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application code cannot replace or expose the snapshot's retained mutable storage.
import ../../../src/codec/state_disputes
let owner = DisputeStateSnapshot(data: nil)
discard owner
