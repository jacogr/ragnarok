# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Reject raw timestamp ownership or unchecked result access.

import ../../../src/state/accumulation_times as state_accumulation_times
var outcome: AccumulationTimesResult[PreparedAccumulationTimes]
outcome.status = AccumulationTimesError.None
