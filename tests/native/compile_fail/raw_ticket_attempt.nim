# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

import ../../../src/codec/tickets
# Host octets require an explicit conversion into ticket-entry identity.
let wrong = Ticket(attempt: 128'u8)
discard wrong
