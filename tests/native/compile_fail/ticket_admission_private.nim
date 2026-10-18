# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default admissions must not expose success storage directly.
import ../../../src/state/ticket_admission
let hidden = default(TicketAdmissionResult)
discard hidden.completed
