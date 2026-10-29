# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict runtime guards for default/failed normalization results and default outcome extraction.

import std/cmdline
import ../../src/state/accumulation/[dispatch as accumulation_dispatch,
    outcome as accumulation_outcome]
var outcome = normalizeAccumulationOutcome(default(AccumulationDispatchResult))
if paramStr(1) == "default":
  outcome = default(AccumulationOutcomeResult[AccumulationOutcome]) # Dynamic selection preserves the runtime check.
case paramStr(1)
of "context":
  let absent = default(AccumulationOutcome).outcomeContext
  discard absent.value # A missing owner cannot expose a selected implication context.
of "info":
  let absent = default(AccumulationOutcome).outcomeInfo
  discard absent.value # A missing owner cannot expose protocol metadata.
else:
  discard outcome.value # Both default and explicit refused normalization have no outcome handle.
