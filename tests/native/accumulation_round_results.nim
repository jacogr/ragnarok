# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict success-extraction probes for initial accumulation results and both immutable plan handles.
## Dynamic command-line modes must terminate at the selected-success contract, never expose defaults.

import std/cmdline
import ../../src/state/accumulation/[round as accumulation_round, queue as accumulation_queue]
import ../../src/codec/state/privileges as state_privileges

# Dynamic selection retains a runtime refusal path rather than a compile-time constant-invalid extraction.
let outcome = if paramStr(1) == "refused":
  planInitialAccumulation(default(AccumulationQueuePlan), default(PrivilegeSnapshot),
    default(AccumulationRoundConfig))
else: default(AccumulationRoundResult[InitialAccumulationRound]) # Defaults carry no completed plan.
let owner = default(InitialAccumulationRound)
let bound = default(BlockAccumulationRound)
case paramStr(1)
of "info": discard owner.roundInfo.value # No default budget/prefix metadata.
of "inputs": discard owner.roundInputs.value # No synthetic input projection.
of "privileges": discard owner.roundPrivileges.value # No unbound fabricated privileges.
of "queue": discard bound.roundBlockQueue.value # No forged admitted queue.
of "projection": discard bound.roundProjection.value # No fabricated pure plan.
else: discard outcome.value # Refused/default results must select success before extraction.
