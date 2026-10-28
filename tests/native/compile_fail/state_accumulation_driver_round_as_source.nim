# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "CompletedBlockAccumulation", "early": ["driveAccumulation(", "[1] expected: CompletedBlockAccumulation but got: BlockAccumulationRound"]}

## Only genuine initial completion can authorize this driver.

import ../../../src/state/accumulation_driver as state_accumulation_driver
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/chain/parameters as chain_parameters
var source: BlockAccumulationRound
discard driveAccumulation(source, default(Parameters), default(AccumulationDriverLimits))
