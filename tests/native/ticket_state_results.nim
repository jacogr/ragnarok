# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually refused publication cannot expose a successful working-store snapshot.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import ../../src/state/[ticket_state, ticket_admission, store]
import ../../src/codec/state_safrole

var state = default(StateStore)
let outcome = if paramStr(1) == "default": default(TicketStateResult) else:
  admitSafroleTicketsState(state, StateTime(1), StateTime(1), [], default(
      TicketAdmissionConfig)) # Actual repeated-slot refusal.
assert paramStr(1) in ["default", "error"] # Unknown selectors cannot pass a result-extraction probe.
assert outcome.error == (if paramStr(1) == "default": TicketAdmissionError.Uninitialized else: TicketAdmissionError.InvalidSlot)
echo outcome.value.commitment.entries
