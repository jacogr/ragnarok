# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Retained output arrays remain private and immutable after capture.
import ../../../src/codec/state_outputs
let owner = default(OutputLogSnapshot)
discard owner.data
