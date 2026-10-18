# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Parent snapshot storage cannot be replaced or exposed by application callers.
import ../../../src/codec/state_consensus
let owner = SafroleStateSnapshot(data: nil)
discard owner
