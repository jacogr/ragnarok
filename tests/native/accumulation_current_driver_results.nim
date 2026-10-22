# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused drivers and terminal owners cannot reveal successful prefixes or inactive parent payloads.
import std/cmdline
import ../../src/chain/parameters
import ../../src/state/[accumulation_current_driver, accumulation_current_sequence,
    accumulation_round]
let owner = default(CurrentSequenceDriverResult[CompletedCurrentAccumulationSequence])
let completed = default(CompletedCurrentAccumulationSequence)
let refused = finishCurrentAccumulationSequence(default(PreparedCurrentContinuation))
let badRun = runCurrentAccumulationSequence(default(CurrentAccumulationSequence), default(
    CurrentContinuationLimits), default(CurrentContinuationExecutionLimits))
let badRoot = runCurrentBlockAccumulationSequence(default(BlockAccumulationRound), default(
    Parameters), default(CurrentSequenceDriverLimits))
case paramStr(1)
of "refused": discard refused.value # Only actual selected success/failure authorizes extraction.
of "initial": discard owner.initialFailure # Only actual selected success/failure authorizes extraction.
of "planning": discard owner.planningFailure # Only actual selected success/failure authorizes extraction.
of "execution": discard owner.executionFailure # Only actual selected success/failure authorizes extraction.
of "plan": discard completed.completedSequencePlan.value # Only actual selected success/failure authorizes extraction.
of "source": discard completed.completedSequenceSource.value # Only actual selected success/failure authorizes extraction.
of "info": discard completed.completedSequenceInfo.value # Only actual selected success/failure authorizes extraction.
of "state": discard completed.completedSequenceState.value # Only actual selected success/failure authorizes extraction.
of "run": discard badRun.value # Only actual selected success/failure authorizes extraction.
of "root": discard badRoot.value # Only actual selected success/failure authorizes extraction.
else: discard owner.value # No synthetic terminal sequence.
