# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default current-guest results cannot reveal successful coverage or inactive parent refusal payloads.
import std/cmdline
import ../../src/state/accumulation_guest_runner
let owner = default(AccumulationGuestResult)
case paramStr(1)
of "service": discard owner.serviceFailure # Only the actual selected ServiceFailure branch exposes this reason.
of "invocation": discard owner.invocationFailure # Only the actual selected InvocationFailure branch exposes this reason.
of "context": discard owner.contextFailure # Only the actual selected ContextFailure branch exposes this reason.
of "machine": discard owner.machineFailure # Only the actual selected MachineFailure branch exposes this reason.
of "dispatch": discard owner.dispatchFailure # Only the actual selected DispatchFailure branch exposes this reason.
of "outcome": discard owner.outcomeFailure # Only the actual selected OutcomeFailure branch exposes this reason.
of "skip": discard owner.skipFailure # Only the actual selected SkipFailure branch exposes this reason.
of "absent": discard owner.absentFailure # Only the actual selected AbsentFailure branch exposes this reason.
of "annulment": discard owner.annulmentFailure # Only the actual selected AnnulmentFailure branch exposes this reason.
of "coverage": discard owner.coverageFailure # Only the actual selected CoverageFailure branch exposes this reason.
else: discard owner.value # No fabricated complete provider coverage.
