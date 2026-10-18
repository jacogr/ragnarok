# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Session callers cannot expose private stream owners, buffers or callback entry points.
import ../../../src/quic/session
var hidden: session.StreamState
