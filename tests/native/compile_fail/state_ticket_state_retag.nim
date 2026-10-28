# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Snapshot result storage/discriminator remain private on default and failed publication.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "status"}

import ../../../src/state/ticket_state as state_ticket_state
import ../../../src/state/ticket_admission as state_ticket_admission
var hidden = default(TicketStateResult)
hidden.status = TicketAdmissionError.None
