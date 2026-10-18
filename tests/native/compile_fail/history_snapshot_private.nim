# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot backing arrays cannot be injected, replaced or exposed by callers.
import ../../../src/codec/state_history
let owner = HistorySnapshot(data: nil)
discard owner
