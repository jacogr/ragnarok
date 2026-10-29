# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["driveAccumulation(", "[1] expected: CompletedBlockAccumulation but got: CompletedAccumulationContinuation"]}

## Only genuine initial completion can authorize this driver.

import ../../../src/state/accumulation/driver as accumulation_driver
import ../../../src/state/accumulation/continuation/execution as accumulation_continuation_execution
import ../../../src/chain/parameters
var source: CompletedAccumulationContinuation
discard driveAccumulation(source, default(Parameters), default(AccumulationDriverLimits))
