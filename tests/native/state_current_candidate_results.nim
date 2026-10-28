# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unrelated/default current candidate alternatives grant no successful update or fabricated child cause.
import std/cmdline
import ../../src/app/candidate as app_candidate
let outcome = default(CurrentCandidateResult)
case paramStr(1)
of "value": discard outcome.value # Access requires its exact selected alternative.
of "prefix": discard outcome.prefixFailure # Access requires its exact selected alternative.
of "report": discard outcome.reportFailure # Access requires its exact selected alternative.
of "queue": discard outcome.queueError # Access requires its exact selected alternative.
of "round": discard outcome.roundError # Access requires its exact selected alternative.
of "completion": discard outcome.completionFailure # Access requires its exact selected alternative.
of "preparation": discard outcome.preparationFailure # Access requires its exact selected alternative.
else: discard outcome.value # Unknown/default input still cannot manufacture current success.
