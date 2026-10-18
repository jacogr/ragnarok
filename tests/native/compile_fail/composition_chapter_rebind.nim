# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Captured chapter/mapping storage cannot be rebound by application callers.
import ../../../src/codec/state_composition
var owner = default(StateChapterSnapshot)
owner.data = nil
