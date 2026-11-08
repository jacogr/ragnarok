# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validate public WebSocket split-owner delivery and joined task cleanup without production RPC.
import std/[assertions, syncio, ioring, threadpool]
import ../../support/websocket_adoption

assert reactorReady() # Importing the stock WebSocket API initializes its I/O runtime.
try:
  runWebSocketTrial[false]()
except ErrorCode as error:
  echo "unexpected WebSocket I/O error: ", error
  assert false, "public WebSocket delivery probe completes"
assert stopped()
initIoRing()
assert stopped() # Shutdown is one-shot; another init does not restart this process's pool.
