# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actually failed admissions cannot expose a fabricated candidate owner.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/state/ticket_admission as state_ticket_admission
import ../../src/codec/state_safrole as codec_state_safrole
import ../../src/codec/state_consensus as codec_state_consensus

let outcome = if paramStr(1) == "default": default(TicketAdmissionResult) else:
  admitSafroleTickets([], StateTime(0), StateTime(1), default(StateEntropyWord), [], default(
      TicketAdmissionConfig)) # Actual invalid policy.
assert paramStr(1) in ["default", "error"] # Unknown selectors are harness failures.
assert outcome.error == (if paramStr(1) == "default": TicketAdmissionError.Uninitialized else: TicketAdmissionError.InvalidConfig)
echo safroleInfo(outcome.value).value.validators
