# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default accumulation-machine results cannot bypass selected-success extraction.

# @@Verification={"group": "privacy", "expected": "completed"}

import ../../../src/state/accumulation_machine as state_accumulation_machine
var outcome: AccumulationMachineResult[PreparedAccumulationMachine]
discard outcome.completed
