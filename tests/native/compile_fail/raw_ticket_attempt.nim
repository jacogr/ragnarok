# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Host octets require an explicit conversion into ticket-entry identity.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: uint8 but wanted: TicketAttempt"}

import ../../../src/codec/tickets
let wrong = Ticket(attempt: 128'u8)
discard wrong
