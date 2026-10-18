# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused transitions and wrong selected causes cannot expose final snapshots or
## private candidates.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/cmdline
import ../../src/state/[report_transition, block_transition, store]
import ../../src/codec/[block_codec, header]
var state = default(StateStore)
let outcome = if paramStr(1) == "error" or paramStr(1) == "nested":
  advanceBlockReports(state, default(OwnedBlock), default(OwnedHeader), [], default(BlockReportConfig))
else: default(BlockReportResult) # No fabricated completed update.
case paramStr(1)
of "stage": discard outcome.stageError # Default has no selected earlier-stage reason.
of "report": discard outcome.reportError # No report check completed or refused.
of "publication": discard outcome.publicationError # No final store publication ran.
of "nested": discard outcome.stageError.value # The actual earlier-stage refusal has no usable intermediate state.
else: discard outcome.value # Default/refused alternatives cannot yield a final snapshot or reports.
