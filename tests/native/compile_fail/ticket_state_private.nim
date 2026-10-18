# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot result storage/discriminator remain private on default and failed publication.
import ../../../src/state/[ticket_state, ticket_admission]
var hidden = default(TicketStateResult)
discard hidden.completed
