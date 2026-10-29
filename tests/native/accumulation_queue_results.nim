# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime extraction-guard executable for default/refused accumulation queue results.
##
## The command-line selector probes priority/count/dependency/bound-plan/admission access; every
## selected path must terminate at the checked success precondition rather than yield a value.

import std/cmdline
import ../../src/state/accumulation/queue as accumulation_queue
import ../../src/state/report/admission as report_admission
import ../../src/codec/state/workqueues as state_workqueues
import ../../src/codec/header
# Runtime selection keeps default/refused extraction in the executable rather than constant folding it.
let outcome = if paramStr(1) == "refused":
  planAccumulationQueues([], [], [], HeaderSlot(0), default(AccumulationQueueConfig))
else: default(AccumulationQueueResult[AccumulationQueuePlan]) # No fabricated success branch.
let owner = default(AccumulationQueuePlan)
case paramStr(1)
of "count": discard owner.accumulationCount.value # Default is not an empty priority sequence.
of "report": discard owner.accumulationAt(AccumulationIndex(0)).value # No default retained report.
of "dependency": discard owner.accumulationDependencyAt(AccumulationIndex(0), WorkQueueHashIndex(
    0)).value # No default hash.
of "bound": discard default(BlockAccumulationQueue).accumulationProjection.value # No forged bound projection.
of "admission": discard default(BlockAccumulationQueue).accumulationAdmission.value # No forged admission certificate.
else: discard outcome.value # Default/refused results contain no payload.
