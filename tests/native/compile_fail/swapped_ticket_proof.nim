# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import ../../../src/codec/tickets
# Entry identities cannot occupy the opaque RingVRF proof domain.
let wrong = Ticket(proof: TicketAttempt(1))
discard wrong
