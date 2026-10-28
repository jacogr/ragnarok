# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["driveAccumulation(", "[1] expected: CompletedBlockAccumulation but got: CompletedAccumulationContinuation"]}

## Only genuine initial completion can authorize this driver.

import ../../../src/state/accumulation_driver as state_accumulation_driver
import ../../../src/state/accumulation_continuation_execution as state_accumulation_continuation_execution
import ../../../src/chain/parameters as chain_parameters
var source: CompletedAccumulationContinuation
discard driveAccumulation(source, default(Parameters), default(AccumulationDriverLimits))
