# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default completion results cannot expose success or a fabricated failed child alternative.
import std/cmdline
import ../../src/state/accumulation_current_completion
let outcome = default(CurrentAccumulationCompletionResult)
case paramStr(1)
of "value": discard outcome.value # A default result has no complete owner.
of "sequence": discard outcome.sequenceFailure # A default result has no failed sequence.
of "statistics": discard outcome.statisticsFailure # An unrelated/default alternative has no actual child.
of "accounts": discard outcome.accountsFailure # An unrelated/default alternative has no actual child.
of "finalization": discard outcome.finalizationFailure # An unrelated/default alternative has no actual child.
of "ready": discard outcome.readyFailure # An unrelated/default alternative has no actual child.
of "recent": discard outcome.recentFailure # An unrelated/default alternative has no actual child.
of "validators": discard outcome.validatorsFailure # An unrelated/default alternative has no actual child.
of "activity": discard outcome.activityFailure # An unrelated/default alternative has no actual child.
of "preimages": discard outcome.preimagesFailure # An unrelated/default alternative has no actual child.
of "authorization": discard outcome.authorizationFailure # An unrelated/default alternative has no actual child.
of "consensus": discard outcome.consensusFailure # An unrelated/default alternative has no actual child.
else: discard outcome.value # Unknown cases still cannot extract a default successful owner.
