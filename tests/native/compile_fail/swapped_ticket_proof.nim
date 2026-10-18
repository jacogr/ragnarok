# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Entry identities cannot occupy the opaque RingVRF proof domain.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/tickets
let wrong = Ticket(proof: TicketAttempt(1))
discard wrong
