# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated negative adoption probe: close a peer while stock WebSocket output is backpressured.
## The assessment runner records exact process termination; a signal is never transport success.
import std/[assertions, syncio]
import ../support/websocket_adoption

try:
  runWebSocketTrial[true]()
except ErrorCode as error:
  echo "unexpected WebSocket I/O error: ", error
  assert false, "slow-peer evaluation reaches its cleanup outcome"
