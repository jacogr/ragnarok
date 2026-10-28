# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused candidate results expose neither finalized successors nor unrelated failed-stage reasons.

import std/cmdline
import ../../src/app/candidate as app_candidate
import ../../src/app/chain as app_chain
import ../../src/codec/block_codec as codec_block_codec

let argument = paramStr(1)
let outcome = if argument == "default": default(ApplicationCandidateResult)
  else: prepareCandidate(default(ApplicationChain), default(OwnedBlock), [], default(
      ApplicationCandidateLimits))
case argument
of "state": discard outcome.stateError # Missing-head refusal never selects StateFailure.
of "block": discard outcome.blockFailure # Missing-head refusal never selects BlockFailure.
of "report": discard outcome.reportFailure # Missing-head refusal never selects ReportFailure.
of "queue": discard outcome.queueError # Missing-head refusal never selects QueueFailure.
of "round": discard outcome.roundError # Missing-head refusal never selects RoundFailure.
of "runner": discard outcome.runnerFailure # Missing-head refusal never selects RunnerFailure.
of "driver": discard outcome.driverFailure # Missing-head refusal never selects DriverFailure.
of "finalization": discard outcome.finalizationFailure # Missing-head refusal never selects FinalizationFailure.
of "enqueue": discard outcome.enqueueError # Missing-head refusal never selects EnqueueFailure.
else: discard outcome.value # Neither defaults nor missing heads contain an execution successor.
