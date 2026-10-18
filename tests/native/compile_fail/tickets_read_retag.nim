# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe callers cannot bypass guarded ticket results through status.
import ../../../src/codec/tickets
var value = default(TicketRead)
value.status = TicketError.None
