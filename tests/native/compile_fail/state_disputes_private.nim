# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application code cannot replace or expose the snapshot's retained mutable storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/state_disputes
let owner = DisputeStateSnapshot(data: nil)
discard owner
