# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Refused recent-history candidates cannot expose values or unrelated stage reasons.

import std/cmdline
import ../../src/state/accumulation_recent as state_accumulation_recent
import ../../src/state/accumulation_ready as state_accumulation_ready

let argument = paramStr(1)
let owner = default(PreparedAccumulationRecent)
let outcome = if argument == "default": default(AccumulationRecentResult[PreparedAccumulationRecent])
  else: prepareAccumulationRecent(default(PreparedAccumulationReady), default(
      AccumulationRecentConfig))
case argument
of "source": discard owner.accumulationRecentSource.value # Defaults never authorize a fabricated source.
of "history": discard owner.accumulationRecentHistory.value # Defaults never authorize a fabricated history.
of "root": discard owner.accumulationRecentRoot.value # Defaults never authorize a fabricated root.
of "entry": discard owner.accumulationRecentEntry.value # Defaults never authorize a fabricated entry.
of "state": discard owner.accumulationRecentState.value # Defaults never authorize a fabricated state.
of "wrong-header": discard outcome.headerError # No HeaderFailure payload under an unrelated alternative.
of "wrong-codec": discard outcome.codecError # No CodecFailure payload under an unrelated alternative.
of "wrong-output": discard outcome.outputError # No OutputFailure payload under an unrelated alternative.
of "wrong-history": discard outcome.historyError # No HistoryFailure payload under an unrelated alternative.
of "wrong-state": discard outcome.stateError # No StateFailure payload under an unrelated alternative.
else: discard outcome.value # Defaults and refused sources carry reasons alone.
