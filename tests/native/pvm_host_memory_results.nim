# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated host byte-range failure-result probes selected by operation and failure reason.
## Each invocation attempts forbidden value extraction after a failed read or write.

import std/cmdline
import ../../src/pvm/machine
var memory = captureMemory([], PageLimit(0)).value
var address = MemoryAddress(65536)
var limit = MemoryByteLimit(1)
case paramStr(2)
of "owner":
  # Absent owners fail even though a valid empty owner would report a permission fault.
  memory = default(Memory)
of "range":
  # Nonempty natural intervals never truncate high address bits.
  address = MemoryAddress(high(uint64))
of "limit":
  # Local policy refuses before sparse permission traversal.
  limit = MemoryByteLimit(0)
else:
  # A valid empty owner has no accessible page at the requested physical address.
  discard
if paramStr(1) == "read":
  # Read failures must not expose even an empty prefix sequence as success.
  discard readBytes(memory, address, MemoryLength(1), limit).value
else:
  # Write failures must not expose a partially changed memory snapshot.
  discard writeBytes(memory, address, [1'u8], limit).value
