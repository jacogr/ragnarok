# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Ready source-shaped storage remains private and immutable after capture.
import ../../../src/codec/state_workqueues
let owner = default(ReadySnapshot)
discard owner.data
