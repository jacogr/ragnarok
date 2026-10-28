# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Entry identities cannot occupy the opaque RingVRF proof domain.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: TicketAttempt but wanted: TicketProof"}

import ../../../src/codec/tickets as codec_tickets
let wrong = Ticket(proof: TicketAttempt(1))
discard wrong
