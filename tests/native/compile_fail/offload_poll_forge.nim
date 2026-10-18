# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Caller code cannot forge pending results or duplicate a live worker-pool owner.
import ../../../src/quic/offload
discard OffloadPollResult(hasCompletion: true)
