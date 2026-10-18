# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass guarded ticket results through count.
import ../../../src/codec/tickets
var value = default(TicketRead)
value.count = 0
