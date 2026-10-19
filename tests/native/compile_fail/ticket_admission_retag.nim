# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot forge successful admission by retagging a failed candidate result.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "privacy", "expected": "status"}

import ../../../src/state/ticket_admission
var hidden = default(TicketAdmissionResult)
hidden.status = TicketAdmissionError.None
