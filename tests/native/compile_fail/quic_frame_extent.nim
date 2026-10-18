# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot expose or forge unchecked framing metadata.
import ../../../src/quic/protocol
var result = default(FrameResult)
discard result.completedExtent
