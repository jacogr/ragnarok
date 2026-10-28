# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused composition cannot expose source, facts, maps or unselected store causes; assignment extents also need success.

import std/cmdline
import ../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../src/state/accumulation_authorization as state_accumulation_authorization
import ../../src/state/report_assignments as state_report_assignments

let argument = paramStr(1)
let owner = default(PreparedAccumulationConsensus)
let outcome = if argument == "default": default(AccumulationConsensusResult[PreparedAccumulationConsensus])
  else: prepareAccumulationConsensus(default(PreparedAccumulationAuthorization), default(
      AccumulationConsensusLimits))
case argument
of "source": discard owner.accumulationConsensusSource.value # No disconnected stage or original-parent authority.
of "info": discard owner.accumulationConsensusInfo.value # No invented slot, chapter count or extent.
of "state": discard owner.accumulationConsensusState.value # No partially composed complete map.
of "wrong-state": discard outcome.stateError # StateFailure is not selected.
of "assignment-bytes": discard default(ReportAssignmentPlan).reportAssignmentByteLength.value # No default canonical entry extent.
else: discard outcome.value # Default/refused alternatives carry reasons alone.
