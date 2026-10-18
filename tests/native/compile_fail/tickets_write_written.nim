# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass guarded ticket results through written.
import ../../../src/codec/tickets
var value = default(TicketWrite)
value.written = 0
