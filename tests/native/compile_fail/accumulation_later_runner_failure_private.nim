# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "refusal"}

## Later runner tags, successes and reason storage remain private.

import ../../../src/state/accumulation/[later_runner as accumulation_later_runner,
    reentry as accumulation_reentry]
var outcome: AccumulationLaterRunnerResult[CompletedAccumulationReentry]
discard outcome.refusal
