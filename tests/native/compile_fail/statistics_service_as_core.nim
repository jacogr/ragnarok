# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Service dictionary ordinals cannot select core positions.
import ../../../src/codec/state_statistics
let owner = default(ActivitySnapshot)
discard coreActivityAt(owner, StatisticsServiceIndex(0))
