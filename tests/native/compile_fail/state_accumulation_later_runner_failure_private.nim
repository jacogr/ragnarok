# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "refusal"}

## Later runner tags, successes and reason storage remain private.

import ../../../src/state/accumulation_later_runner as state_accumulation_later_runner
import ../../../src/state/accumulation_reentry as state_accumulation_reentry
var outcome: AccumulationLaterRunnerResult[CompletedAccumulationReentry]
discard outcome.refusal
