# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default admissions must not expose success storage directly.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/ticket/admission as ticket_admission
let hidden = default(TicketAdmissionResult)
discard hidden.completed
