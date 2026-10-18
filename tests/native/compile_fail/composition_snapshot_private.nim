# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot obtain or edit private mapping/child storage.
import ../../../src/codec/state_composition
let owner = default(StateSnapshot)
discard owner.data
