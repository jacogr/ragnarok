# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact current-profile refusals for the unchanged pinned historical block transport.
import std/assertions
import ../../src/state/[safrole_transition, safrole_authentication, ticket_admission]

proc checkHistoricalRefusal*(name: string, outcome: SafroleTransitionResult) =
  ## Two historical submitted-ticket batches fail before sealing; the remaining eight fail their old seal.
  if name in ["safrole/12", "safrole/13"]:
    assert outcome.error == SafroleTransitionError.AdmissionFailure, name & " " & $outcome.error
    assert outcome.admissionError == TicketAdmissionError.InvalidProof
  else:
    assert outcome.error == SafroleTransitionError.AuthenticationFailure, name & " " & $outcome.error
    assert outcome.authenticationError == SafroleAuthError.InvalidSeal
