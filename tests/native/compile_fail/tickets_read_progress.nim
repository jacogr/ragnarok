# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass guarded ticket results through consumed.
import ../../../src/codec/tickets
var value = default(TicketRead)
value.consumed = 0
