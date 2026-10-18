# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass guarded ticket results through byteWritten.
import ../../../src/codec/tickets
var value = default(TicketWrite)
echo value.byteWritten
